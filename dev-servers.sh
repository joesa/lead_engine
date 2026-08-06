#!/usr/bin/env bash
#
# Start / stop / restart the local dev servers for this workspace.
#
#   ./dev-servers.sh start      # free the ports, then start everything
#   ./dev-servers.sh stop       # stop everything and free the ports
#   ./dev-servers.sh restart    # stop + start
#   ./dev-servers.sh status     # what is running / listening
#
# A single server can be targeted by name, e.g.
#   ./dev-servers.sh restart dashboard
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$ROOT/.dev-servers"
LOG_DIR="$RUN_DIR/logs"

# name|directory|port|command
SERVERS=(
  "renderer|custom-closets-websites|3000|npm run dev -- -p 3000"
  "dashboard|closet-dashboard|3001|npm run dev -- -p 3001"
  "widget|closet-widget|5173|npm run dev -- --port 5173"
)

READY_TIMEOUT=90

field() { echo "$1" | cut -d'|' -f"$2"; }

selected_servers() {
  local want="${1:-}"
  local entry found=0
  for entry in "${SERVERS[@]}"; do
    if [[ -z "$want" || "$(field "$entry" 1)" == "$want" ]]; then
      echo "$entry"
      found=1
    fi
  done
  if [[ "$found" -eq 0 ]]; then
    echo "Unknown server '$want'. Known: $(for e in "${SERVERS[@]}"; do printf '%s ' "$(field "$e" 1)"; done)" >&2
    exit 1
  fi
}

# lsof misses Next's IPv6 wildcard listeners here, so ss/fuser are queried too.
listeners_on_port() {
  {
    printf '%s\n' "$(ss -ltnpH "sport = :$1" 2>/dev/null | grep -oE 'pid=[0-9]+' | cut -d= -f2)"
    printf '%s\n' "$(fuser -n tcp "$1" 2>/dev/null)"
    printf '%s\n' "$(lsof -t -sTCP:LISTEN -i "tcp:$1" 2>/dev/null)"
  } | tr -s ' ' '\n' | grep -E '^[0-9]+$' | sort -u
}

# Kill every process listening on a port, including its child processes
# (`next dev` / `vite` fork workers that keep the port bound otherwise).
free_port() {
  local port="$1" label="${2:-}"
  local pids pid pgid own_pgid killed=0

  own_pgid="$(ps -o pgid= -p $$ | tr -d ' ')"

  pids="$(listeners_on_port "$port")"
  [[ -z "$pids" ]] && return 0

  for pid in $pids; do
    pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
    echo "  port $port busy${label:+ ($label)}: killing pid $pid ($(ps -o comm= -p "$pid" 2>/dev/null | tr -d ' '))"
    if [[ -n "$pgid" && "$pgid" != "1" && "$pgid" != "$own_pgid" ]]; then
      kill -TERM -- "-$pgid" 2>/dev/null
    else
      kill -TERM "$pid" 2>/dev/null
    fi
    killed=1
  done

  [[ "$killed" -eq 1 ]] || return 0

  for _ in $(seq 1 20); do
    [[ -z "$(listeners_on_port "$port")" ]] && return 0
    sleep 0.25
  done

  # Still bound after SIGTERM - escalate.
  for pid in $(listeners_on_port "$port"); do
    pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
    if [[ -n "$pgid" && "$pgid" != "1" && "$pgid" != "$own_pgid" ]]; then
      kill -KILL -- "-$pgid" 2>/dev/null
    else
      kill -KILL "$pid" 2>/dev/null
    fi
  done
  sleep 0.5

  if [[ -n "$(listeners_on_port "$port")" ]]; then
    echo "  ERROR: port $port is still in use" >&2
    return 1
  fi
}

stop_one() {
  local entry="$1"
  local name port pidfile pid pgid
  name="$(field "$entry" 1)"
  port="$(field "$entry" 3)"
  pidfile="$RUN_DIR/$name.pid"

  if [[ -f "$pidfile" ]]; then
    pid="$(cat "$pidfile")"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      # $pid is the process-group leader of its own session (see start_one).
      pgid="$pid"
      echo "  stopping $name (pid $pid)"
      kill -TERM -- "-${pgid}" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
      for _ in $(seq 1 20); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.25
      done
      kill -0 "$pid" 2>/dev/null && kill -KILL -- "-${pgid:-$pid}" 2>/dev/null
    fi
    rm -f "$pidfile"
  fi

  # Always reclaim the port, even if it was taken by something we did not start.
  free_port "$port" "$name"
}

start_one() {
  local entry="$1"
  local name dir port cmd pidfile logfile pid
  name="$(field "$entry" 1)"
  dir="$(field "$entry" 2)"
  port="$(field "$entry" 3)"
  cmd="$(field "$entry" 4)"
  pidfile="$RUN_DIR/$name.pid"
  logfile="$LOG_DIR/$name.log"

  if [[ ! -d "$ROOT/$dir" ]]; then
    echo "  SKIP $name: $dir not found" >&2
    return 1
  fi

  free_port "$port" "$name" || return 1

  : > "$logfile"
  rm -f "$pidfile"
  # setsid + exec: the recorded pid is the session/process-group leader of the
  # whole tree (npm -> next/vite -> workers), so one signal takes it all down.
  ( cd "$ROOT/$dir" && setsid bash -c "echo \$\$ > '$pidfile'; exec $cmd" >>"$logfile" 2>&1 & )
  for _ in $(seq 1 50); do
    [[ -s "$pidfile" ]] && break
    sleep 0.1
  done
  pid="$(cat "$pidfile" 2>/dev/null)"
  if [[ -z "$pid" ]]; then
    echo "  ERROR: $name failed to launch - see $logfile" >&2
    return 1
  fi
  echo "  starting $name on :$port (pid $pid, log $logfile)"

  for _ in $(seq 1 $((READY_TIMEOUT * 2))); do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "  ERROR: $name exited during startup - see $logfile" >&2
      tail -n 20 "$logfile" >&2
      rm -f "$pidfile"
      return 1
    fi
    if curl -fsS -o /dev/null --max-time 2 "http://localhost:$port/" 2>/dev/null; then
      echo "  ready:    $name -> http://localhost:$port"
      return 0
    fi
    sleep 0.5
  done

  echo "  WARNING: $name did not respond on :$port within ${READY_TIMEOUT}s (still running, see $logfile)" >&2
  return 0
}

status() {
  local entry name port pidfile pid pids
  printf '%-12s %-6s %-10s %s\n' NAME PORT STATE DETAIL
  for entry in "${SERVERS[@]}"; do
    name="$(field "$entry" 1)"
    port="$(field "$entry" 3)"
    pidfile="$RUN_DIR/$name.pid"
    pid=""
    [[ -f "$pidfile" ]] && pid="$(cat "$pidfile")"
    pids="$(listeners_on_port "$port" | tr '\n' ' ')"

    if [[ -n "$pids" ]]; then
      if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        printf '%-12s %-6s %-10s %s\n' "$name" "$port" "running" "pid $pid | http://localhost:$port"
      else
        printf '%-12s %-6s %-10s %s\n' "$name" "$port" "foreign" "port held by pid(s): $pids"
      fi
    else
      printf '%-12s %-6s %-10s %s\n' "$name" "$port" "stopped" "-"
    fi
  done
}

mkdir -p "$RUN_DIR" "$LOG_DIR"

action="${1:-start}"
target="${2:-}"
mapfile -t chosen < <(selected_servers "$target")

case "$action" in
  start)
    echo "Starting dev servers${target:+ ($target)}..."
    rc=0
    for entry in "${chosen[@]}"; do start_one "$entry" || rc=1; done
    echo
    status
    exit "$rc"
    ;;
  stop)
    echo "Stopping dev servers${target:+ ($target)}..."
    for entry in "${chosen[@]}"; do stop_one "$entry"; done
    echo
    status
    ;;
  restart)
    echo "Restarting dev servers${target:+ ($target)}..."
    for entry in "${chosen[@]}"; do stop_one "$entry"; done
    rc=0
    for entry in "${chosen[@]}"; do start_one "$entry" || rc=1; done
    echo
    status
    exit "$rc"
    ;;
  status)
    status
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status} [renderer|dashboard|widget]" >&2
    exit 1
    ;;
esac
