#!/usr/bin/env bash
# Link the kde-desktop skill and CLI from this checkout into the user's environment.
# Idempotent: re-running repairs links; it never overwrites a real file or directory.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd -P)"
SKILL_SRC="$REPO/skills/kde-desktop"
CLI_SRC="$SKILL_SRC/scripts/kde-desktop"
SKILL_DST="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}/kde-desktop"
CLI_DST="${BIN_DIR:-$HOME/.local/bin}/kde-desktop"

log() {  # level context message [error]
  printf '{"timestamp":"%s","level":"%s","context":"%s","message":"%s"%s}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" "$1" "$2" "$3" "${4:+,\"error\":\"$4\"}" >&2
}

link() {  # source destination
  local src="$1" dst="$2"
  if [[ ! -e "$src" ]]; then
    log error link "source missing" "$src"; exit 1
  fi
  mkdir -p "$(dirname "$dst")"
  if [[ -L "$dst" ]]; then
    if [[ "$(readlink -f "$dst")" == "$(readlink -f "$src")" ]]; then
      log info link "already linked: $dst"; return
    fi
    log warn link "replacing link $dst (was -> $(readlink "$dst"))"
    ln -sfn "$src" "$dst"
  elif [[ -e "$dst" ]]; then
    log error link "refusing to overwrite existing non-link path" "$dst"; exit 1
  else
    ln -s "$src" "$dst"
  fi
  log info link "linked $dst -> $src"
}

log info install "starting" ""
chmod +x "$CLI_SRC"
link "$SKILL_SRC" "$SKILL_DST"
link "$CLI_SRC" "$CLI_DST"
case ":$PATH:" in
  *":$(dirname "$CLI_DST"):"*) ;;
  *) log warn install "$(dirname "$CLI_DST") is not on PATH; add it to use kde-desktop directly" ;;
esac
if [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v kde-desktop >/dev/null; then
  log info install "running kde-desktop doctor"
  kde-desktop doctor || log warn install "doctor exited non-zero"
else
  log info install "not in a Wayland session; run 'kde-desktop doctor' from the desktop"
fi
log info install "done"
