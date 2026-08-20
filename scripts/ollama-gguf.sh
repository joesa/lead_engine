#!/usr/bin/env bash
#
# Download a GGUF model from Hugging Face and register it with Ollama.
#
# Handles quants that ship as multiple split .gguf shards (Ollama's own import
# path chokes on very large single blobs -- see ollama/ollama#5245), by merging
# the shards with llama-gguf-split when it is available, or by pointing the
# Modelfile at shard 00001 otherwise (recent Ollama follows the split itself).
#
# Usage:
#   ollama-gguf.sh <hf-repo> <quant> [options]
#   ollama-gguf.sh --list <hf-repo>
#
# Examples:
#   ollama-gguf.sh unsloth/Qwen3-Coder-Next-GGUF Q4_1
#   ollama-gguf.sh unsloth/Qwen3-Coder-Next-GGUF Q4_1 --name qwen3-coder-next --run
#   ollama-gguf.sh unsloth/gpt-oss-120b-GGUF Q8_0 --dir ~/models --no-keep
#   ollama-gguf.sh --list unsloth/Qwen3-Coder-Next-GGUF

set -euo pipefail

die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarn:\033[0m %s\n' "$*" >&2; }

usage() {
  sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'
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
[[ "$REPO" == */* ]] || die "repo must look like 'org/model-GGUF', got '$REPO'"

# Easy mistake: passing the quant Ollama-style as part of the repo name.
if [[ "$REPO" == *:* ]]; then
  if [[ $LIST_ONLY -eq 1 ]]; then
    die "--list takes the repo only -- drop the ':' suffix:
  $0 --list ${REPO%%:*}"
  fi
  die "repo and quant are separate arguments, not 'repo:quant':
  $0 ${REPO%%:*} ${REPO#*:}"
fi

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
slug() { tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._-' '-' | sed 's/-\{2,\}/-/g; s/^-//; s/-$//'; }

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
  --include "${QUANT}/*.gguf" "${QUANT}*.gguf" "*${QUANT}*.gguf" \
  --local-dir "$DEST" \
  "${HF_TOKEN_ARG[@]}"

# hf preserves the repo's directory layout, so the files may land in $DEST or
# in $DEST/<quant>/. Collect whatever .gguf actually arrived.
mapfile -t SHARDS < <(find "$DEST" -type f -name '*.gguf' | sort)
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

  SPLIT_BIN="$(command -v llama-gguf-split || command -v gguf-split || true)"
  MERGED="${FIRST/-00001-of-*.gguf/-merged.gguf}"

  if [[ -f "$MERGED" ]]; then
    info "Reusing existing merge: $(basename "$MERGED")"
    GGUF="$MERGED"
  elif [[ -n "$SPLIT_BIN" ]]; then
    info "Merging ${#SHARDS[@]} shards with $(basename "$SPLIT_BIN")..."
    "$SPLIT_BIN" --merge "$FIRST" "$MERGED"
    GGUF="$MERGED"
    if [[ $KEEP -eq 0 ]]; then
      info "Removing shards"
      for f in "${SHARDS[@]}"; do rm -f "$f"; done
    fi
  else
    warn "llama-gguf-split not found; pointing Ollama at the first shard instead."
    warn "Ollama >= 0.3 follows split GGUF from shard 1. If import fails, install"
    warn "llama.cpp (brew install llama.cpp) and re-run to merge first."
    GGUF="$FIRST"
  fi
fi

info "GGUF    $GGUF ($(du -h "$GGUF" | cut -f1))"

# --------------------------------------------------------------- create ------
if [[ $DO_CREATE -eq 0 ]]; then
  info "Skipping ollama create (--no-create). Modelfile line would be:"
  printf '  FROM %s\n' "$GGUF"
  exit 0
fi

MODELFILE="${DEST}/Modelfile"
printf 'FROM %s\n' "$GGUF" > "$MODELFILE"

info "ollama create $MODEL"
ollama create "$MODEL" -f "$MODELFILE"

info "Done. Run it with:  ollama run $MODEL"
[[ $DO_RUN -eq 0 ]] || exec ollama run "$MODEL"
