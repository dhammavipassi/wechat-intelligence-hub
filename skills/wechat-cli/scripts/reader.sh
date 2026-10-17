#!/usr/bin/env bash
set -euo pipefail

codex_root="${CODEX_HOME:-$HOME/.codex}"
installed="$codex_root/share/wechat-intelligence-hub/projects/rion-wechat-reader/rion_wechat_reader.py"
repo_candidate="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/projects/rion-wechat-reader/rion_wechat_reader.py"
bundled_cli="$codex_root/bin/rion-wechat-cli"

# 引擎解释器由 reader 自己解析，不继承调用方的 venv。
# 原因：各管道会把自身 venv 的 bin 目录排进 PATH，而管道 venv 不含 reader 运行依赖
# （zstandard 解 WCDB 压缩消息），盲取 PATH 里的 python3 会让读取整体失败。
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

if [ -n "${RION_WECHAT_CLI_BIN:-}" ]; then
  exec "$RION_WECHAT_CLI_BIN" "$@"
fi

if [ -n "${RION_WECHAT_READER_BIN:-}" ]; then
  exec "$RION_WECHAT_READER_BIN" "$@"
fi

if command -v rion-wechat-cli >/dev/null 2>&1; then
  exec "$(command -v rion-wechat-cli)" "$@"
fi

if [ -x "$bundled_cli" ]; then
  exec "$bundled_cli" "$@"
fi

if [ -f "$installed" ] || [ -f "$repo_candidate" ]; then
  reader_python="$(resolve_reader_python)"
  if [ -z "$reader_python" ]; then
    echo "no python3 with the reader runtime deps (zstandard) found; set RION_WECHAT_READER_PYTHON" >&2
    exit 127
  fi
  if [ -f "$installed" ]; then
    exec "$reader_python" "$installed" "$@"
  fi
  exec "$reader_python" "$repo_candidate" "$@"
fi

echo "rion-wechat-cli engine not found. Reinstall the wechat-cli Skill." >&2
exit 127
