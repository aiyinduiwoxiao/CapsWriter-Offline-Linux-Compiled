#!/usr/bin/env bash
# 麦克风测试: 录制 5 秒 → 发送 ASR → 打印结果
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source .venv/bin/activate
python test_mic.py
