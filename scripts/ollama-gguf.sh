#!/usr/bin/env bash
#
# Download a GGUF model from Hugging Face and register it with Ollama.
#
# Handles quants that ship as multiple split .gguf shards (see ollama/ollama#5245)
# by merging them with llama-gguf-split into the single file Ollama needs.
#
# Merging is not optional in practice. Ollama 0.32.14 rejects split GGUF from
# every angle tested: FROM shard-1, FROM a directory, one FROM per shard, a
# hand-built /api/create carrying all shards, and `ollama create` run from
# inside the shard directory (the maintainer's own advice in ollama#5245).
# All five deliver every shard to the server and all five die with
#   Error: split GGUF "...-00001-of-000NN.gguf" has 1 shards, expected NN
# so --no-merge is useful for llama.cpp, not for `ollama create` today.
#
# Usage:
#   ollama-gguf.sh <hf-repo> <quant> [options]
#   ollama-gguf.sh --list <hf-repo>
#
# Examples:
#   ollama-gguf.sh unsloth/Qwen3-Coder-Next-GGUF Q4_1
#   ollama-gguf.sh unsloth/Qwen3-Coder-Next-GGUF Q4_1 --name qwen3-coder-next --run
#   ollama-gguf.sh unsloth/gpt-oss-120b-GGUF Q8_0 --dir ~/models --no-keep
#   ollama-gguf.sh unsloth/DeepSeek-V4-Flash-0731-GGUF UD-Q8_K_XL --no-merge --no-create
#   ollama-gguf.sh --list unsloth/Qwen3-Coder-Next-GGUF

set -euo pipefail

die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarn:\033[0m %s\n' "$*" >&2; }

# A GGUF file begins with the four-byte magic "GGUF". Checking it is free, and
# it turns the two silent failure modes here -- a truncated download and a
# merge that died partway -- into an error naming the offending file, instead
# of Ollama's opaque "supplied file was not in GGUF format" after a long run.
is_gguf() {
  [[ -s "$1" ]] || return 1
  [[ "$(head -c 4 "$1" 2>/dev/null)" == "GGUF" ]]
}

# Under git-bash on Windows, $PATH-style args are POSIX paths (/c/Users/...)
# but `ollama` is a native Windows binary that can't resolve them -- it can't
# find the file, silently treats FROM's value as a model name to pull instead,
# and fails with a confusing "invalid model name" rather than a file error.
to_ollama_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    printf '%s' "$1"
  fi
}

usage() {
  sed -n '3,25p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

# ---------------------------------------------------------------- args -------
REPO=""
QUANT=""
NAME=""
TAG=""
BASE_DIR="${OLLAMA_GGUF_DIR:-$PWD/gguf-models}"
DO_RUN=0
DO_CREATE=1
KEEP=1
DO_MERGE=1
LIST_ONLY=0
FORCE=0
HF_TOKEN_ARG=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)      usage 0 ;;
    -l|--list)      LIST_ONLY=1; shift ;;
    -n|--name)      NAME="${2:?--name needs a value}"; shift 2 ;;
    -t|--tag)       TAG="${2:?--tag needs a value}"; shift 2 ;;
    -d|--dir)       BASE_DIR="${2:?--dir needs a value}"; shift 2 ;;
    --token)        HF_TOKEN_ARG=(--token "${2:?--token needs a value}"); shift 2 ;;
    --run)          DO_RUN=1; shift ;;
    --no-create)    DO_CREATE=0; shift ;;
    --no-keep|--delete-download) KEEP=0; shift ;;
    --no-merge)     DO_MERGE=0; shift ;;
    --force)        FORCE=1; shift ;;
    -*)             die "unknown option: $1 (try --help)" ;;
    *)
      if   [[ -z "$REPO"  ]]; then REPO="$1"
      elif [[ -z "$QUANT" ]]; then QUANT="$1"
      else die "unexpected argument: $1"
      fi
      shift ;;
  esac
done

[[ -n "$REPO" ]] || usage 1

# Easy mistake: passing the quant Ollama-style as part of the repo name.
# Checked before the org/model-GGUF shape check below so this more specific
# hint wins even when the repo also lacks an 'org/' prefix.
if [[ "$REPO" == *:* ]]; then
  if [[ $LIST_ONLY -eq 1 ]]; then
    die "--list takes the repo only -- drop the ':' suffix:
  $0 --list ${REPO%%:*}"
  fi
  die "repo and quant are separate arguments, not 'repo:quant':
  $0 ${REPO%%:*} ${REPO#*:}"
fi

[[ "$REPO" == */* ]] || die "repo must look like 'org/model-GGUF', got '$REPO'"

# ---------------------------------------------------------------- deps -------
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found. $2"; }

# --------------------------------------------------------------- --list ------
if [[ $LIST_ONLY -eq 1 ]]; then
  need curl "Install curl."
  need jq   "Install jq (apt install jq / brew install jq)."
  info "Quantizations available in $REPO"
  curl -fsSL "https://huggingface.co/api/models/${REPO}/tree/main" \
    | jq -r '.[] | select(.type=="directory") | "  " + .path' \
    || die "could not read the repo tree (private repo? use HF_TOKEN)"
  # Quants published as loose files at the repo root rather than per-quant dirs.
  curl -fsSL "https://huggingface.co/api/models/${REPO}/tree/main" \
    | jq -r '.[] | select(.type=="file") | select(.path|test("\\.gguf$")) | "  " + .path'
  exit 0
fi

[[ -n "$QUANT" ]] || die "missing quantization (e.g. Q4_1, Q8_0, UD-Q4_K_XL). Try: $0 --list $REPO"

need hf "Install it with: pip install -U 'huggingface_hub[cli]'"
[[ $DO_CREATE -eq 0 ]] || need ollama "Install from https://ollama.com/download"

# --------------------------------------------------------------- naming ------
# unsloth/Qwen3-Coder-Next-GGUF + Q4_1  ->  qwen3-coder-next:q4_1
# Dots become hyphens rather than disappearing, so Qwen3.8 -> qwen3-8 keeps
# the version boundary readable.
slug() { tr '[:upper:]' '[:lower:]' | tr '.' '-' | tr -c 'a-z0-9_-' '-' | sed 's/-\{2,\}/-/g; s/^-//; s/-$//'; }

if [[ -z "$NAME" ]]; then
  NAME="$(printf '%s' "${REPO##*/}" | sed 's/[-_.]\{0,1\}GGUF$//I' | slug)"
fi
[[ -n "$TAG" ]] || TAG="$(printf '%s' "$QUANT" | slug)"
MODEL="${NAME}:${TAG}"

DEST="${BASE_DIR}/$(printf '%s' "${REPO##*/}" | slug)/${QUANT}"

if [[ $DO_CREATE -eq 1 && $FORCE -eq 0 ]] && ollama list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$MODEL"; then
  die "ollama already has '$MODEL' (pass --force to rebuild, or --tag to pick another tag)"
fi

info "repo    $REPO"
info "quant   $QUANT"
info "model   $MODEL"
info "dir     $DEST"

# ------------------------------------------------------------- download ------
mkdir -p "$DEST"
info "Downloading (resumes if interrupted)..."
hf download "$REPO" \
  --include "${QUANT}/*.gguf" \
  --include "${QUANT}*.gguf" \
  --include "*${QUANT}*.gguf" \
  --local-dir "$DEST" \
  "${HF_TOKEN_ARG[@]}"

# hf preserves the repo's directory layout, so the files may land in $DEST or
# in $DEST/<quant>/. Collect whatever .gguf actually arrived.
#
# -merged.gguf is this script's own output from an earlier run, not something
# hf downloaded. Counting it as a shard made a second run report one file too
# many, inflate the du total, and -- worst -- feed the merge output back into
# the shard list it was built from.
mapfile -t SHARDS < <(find "$DEST" -type f -name '*.gguf' ! -name '*-merged.gguf' | sort)
[[ ${#SHARDS[@]} -gt 0 ]] || die "no .gguf files matched quant '$QUANT' in $REPO. Try: $0 --list $REPO"

info "Got ${#SHARDS[@]} file(s), $(du -sh "$DEST" | cut -f1) total"

# ---------------------------------------------------------------- merge ------
GGUF="${SHARDS[0]}"

if [[ ${#SHARDS[@]} -gt 1 ]]; then
  FIRST=""
  for f in "${SHARDS[@]}"; do
    [[ "$f" == *-00001-of-*.gguf ]] && FIRST="$f" && break
  done
  [[ -n "$FIRST" ]] || die "multiple .gguf files but no *-00001-of-*.gguf shard; not sure how to combine them:
$(printf '  %s\n' "${SHARDS[@]}")"

  # $LLAMA_GGUF_SPLIT wins so a newer llama.cpp can be used without reordering
  # PATH. This matters: llama-gguf-split cannot parse tensor types newer than
  # the build itself, and it fails only after the download finishes. A Dec-2024
  # build dies with "invalid type (39)" -- GGML_TYPE_MXFP4 -- on any quant that
  # uses it, which includes unsloth's UD-* DeepSeek quants.
  SPLIT_BIN="${LLAMA_GGUF_SPLIT:-$(command -v llama-gguf-split || command -v gguf-split || true)}"
  if [[ -n "$SPLIT_BIN" && ! -x "$SPLIT_BIN" ]]; then
    die "LLAMA_GGUF_SPLIT is not an executable: $SPLIT_BIN"
  fi
  MERGED="${FIRST/-00001-of-*.gguf/-merged.gguf}"

  # A leftover -merged.gguf is only worth reusing if it is a complete GGUF.
  # An interrupted merge -- or one that ran the disk out, which is easy here
  # since the merge writes a second full copy of the model -- leaves a 0-byte
  # or truncated file behind. Reusing that blindly made every subsequent run
  # fail identically, at the very last step, in `ollama create`.
  if [[ -e "$MERGED" ]] && ! is_gguf "$MERGED"; then
    warn "Discarding unusable merge from an earlier run ($(du -h "$MERGED" | cut -f1)): $(basename "$MERGED")"
    rm -f "$MERGED"
  fi

  if [[ -f "$MERGED" ]]; then
    info "Reusing existing merge: $(basename "$MERGED")"
    GGUF="$MERGED"
  elif [[ $DO_MERGE -eq 0 ]]; then
    info "Skipping merge (--no-merge); pointing at shard 1."
    [[ $DO_CREATE -eq 0 ]] || warn "Ollama rejects split GGUF (see the note at the top of this script)."
    GGUF="$FIRST"
  elif [[ -n "$SPLIT_BIN" ]]; then
    # The merged file is a second copy of the whole model, so the volume needs
    # as much free space again as the shards already occupy. Checking up front
    # beats discovering it hours in, with a half-written file left behind.
    need_kb=0
    for f in "${SHARDS[@]}"; do
      need_kb=$(( need_kb + $(du -k "$f" | cut -f1) ))
    done
    free_kb="$(df -Pk "$DEST" 2>/dev/null | awk 'NR==2{print $4}')"
    if [[ -n "$free_kb" ]] && (( free_kb < need_kb )); then
      die "not enough free space to merge: need ~$(( need_kb / 1048576 ))G, have ~$(( free_kb / 1048576 ))G on the volume holding
  $DEST
  Free up space, or re-run with --no-merge to import from shard 1 instead."
    fi

    info "Merging ${#SHARDS[@]} shards with $(basename "$SPLIT_BIN")..."
    # Write to a .partial and rename only after the result validates, so an
    # interrupted merge can never leave something the next run will reuse.
    PARTIAL="${MERGED}.partial"
    rm -f "$PARTIAL"
    trap 'rm -f "$PARTIAL"' EXIT
    "$SPLIT_BIN" --merge "$FIRST" "$PARTIAL"
    is_gguf "$PARTIAL" || die "merge finished but produced no usable GGUF (check disk space): $PARTIAL"
    mv -f "$PARTIAL" "$MERGED"
    trap - EXIT
    GGUF="$MERGED"
    if [[ $KEEP -eq 0 ]]; then
      info "Removing shards"
      for f in "${SHARDS[@]}"; do rm -f "$f"; done
    fi
  else
    warn "llama-gguf-split not found, so the shards cannot be merged."
    warn "Ollama will refuse the split ('has 1 shards, expected N'). Install"
    warn "llama.cpp (brew install llama.cpp) and re-run to merge first."
    GGUF="$FIRST"
  fi
fi

is_gguf "$GGUF" || die "not a GGUF file: $GGUF
  Size is $(du -h "$GGUF" | cut -f1). A truncated download or a failed merge looks exactly like this.
  Delete that file and re-run."

info "GGUF    $GGUF ($(du -h "$GGUF" | cut -f1))"

# --------------------------------------------------------------- create ------
if [[ $DO_CREATE -eq 0 ]]; then
  info "Skipping ollama create (--no-create). Modelfile line would be:"
  printf '  FROM %s\n' "$(to_ollama_path "$GGUF")"
  exit 0
fi

MODELFILE="${DEST}/Modelfile"
printf 'FROM %s\n' "$(to_ollama_path "$GGUF")" > "$MODELFILE"

info "ollama create $MODEL"
ollama create "$MODEL" -f "$MODELFILE"

info "Done. Run it with:  ollama run $MODEL"
[[ $DO_RUN -eq 0 ]] || exec ollama run "$MODEL"
