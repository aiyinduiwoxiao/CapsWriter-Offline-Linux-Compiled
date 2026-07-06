#!/usr/bin/env bash
# 启动 CapsWriter 客户端 (麦克风录制 + 快捷键)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 自动适配 runtime Python（离线 bootstrap 安装的）
if [[ -x runtime/python/bin/python3.11 ]]; then
    export LD_LIBRARY_PATH="$SCRIPT_DIR/runtime/python/lib:${LD_LIBRARY_PATH:-}"
fi

if [[ -f .venv/bin/activate ]]; then
    source .venv/bin/activate
else
    echo "错误: 虚拟环境不存在，请先运行 bash setup.sh"
    exit 1
fi

python -m core.client.app "$@"
