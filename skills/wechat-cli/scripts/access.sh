#!/usr/bin/env bash
set -euo pipefail
codex_root="${CODEX_HOME:-$HOME/.codex}"

resolve_reader_python() {
  if [ -n "${RION_WECHAT_READER_PYTHON:-}" ]; then
    printf '%s' "$RION_WECHAT_READER_PYTHON"
    return 0
  fi
  local candidate
  for candidate in \
    "$HOME/.local/share/rion-wechat-cli/venv/bin/python" \
    "$codex_root/share/rion-wechat-cli/venv/bin/python" \
    "$(command -v python3 || true)" \
    /opt/homebrew/bin/python3 \
    /usr/local/bin/python3 \
    /usr/bin/python3; do
    [ -n "$candidate" ] && [ -x "$candidate" ] || continue
    if "$candidate" -c 'import zstandard' >/dev/null 2>&1; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  command -v python3 || true
}

if command -v rion-wechat-access >/dev/null 2>&1; then
  exec "$(command -v rion-wechat-access)" "$@"
fi
if [ -x "$codex_root/bin/rion-wechat-access" ]; then
  exec "$codex_root/bin/rion-wechat-access" "$@"
fi
installed="$codex_root/share/wechat-intelligence-hub/projects/rion-wechat-reader/rion_wechat_access.py"
repo_candidate="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/projects/rion-wechat-reader/rion_wechat_access.py"
reader_py="$(resolve_reader_python)"
if [ -f "$installed" ]; then
  exec "${reader_py:-python3}" "$installed" "$@"
fi
if [ -f "$repo_candidate" ]; then
  exec "${reader_py:-python3}" "$repo_candidate" "$@"
fi
echo "Optional access helper not installed; update the wechat-cli Skill." >&2
exit 127
