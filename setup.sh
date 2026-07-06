#!/usr/bin/env bash
# ============================================================
# CapsWriter Offline v2.6 — 多架构部署脚本
# 支持: x86_64 (amd64) / aarch64 (arm64)
#
# 用法:
#   在线:   bash setup.sh
#   离线:   bash setup.sh --offline
#   离线含 Python: bash setup.sh --offline --bootstrap
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

OFFLINE=false; SKIP_SYSTEM=false; BOOTSTRAP=false
PYTHON="python3.14"

usage() {
    cat <<EOF
CapsWriter Offline — 多架构部署脚本

用法: bash setup.sh [选项]

选项:
  --offline       离线模式，从本地 deps/ 安装 Python 包
  --bootstrap     从本地归档安装 Python + uv
  --skip-system   跳过系统级依赖安装
  --python PATH   指定 Python 解释器路径
  -h, --help      显示此帮助

示例:
  bash setup.sh                                    # 在线
  bash setup.sh --offline                           # 离线 (系统有 Python)
  bash setup.sh --offline --bootstrap               # 完全离线
  bash setup.sh --offline --bootstrap --skip-system # 离线+跳过apt
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --offline)      OFFLINE=true; shift ;;
        --bootstrap)    BOOTSTRAP=true; shift ;;
        --skip-system)  SKIP_SYSTEM=true; shift ;;
        --python)       PYTHON="$2"; shift 2 ;;
        -h|--help)      usage ;;
        *) echo -e "${RED}未知参数: $1${NC}"; usage ;;
    esac
done

# ============================================================
# 架构检测
# ============================================================
HOST_ARCH=$(uname -m)
case "$HOST_ARCH" in
    x86_64)
        ARCH_LABEL="x86_64 (amd64)"
        UV_PATTERN="uv-x86_64*.tar.gz"
        PY_PATTERN="cpython-*x86_64*.tar.gz"
        SYSDEPS_DIR="sysdeps"
        DEPS_DIR="deps"
        ;;
    aarch64|arm64)
        ARCH_LABEL="aarch64 (arm64)"
        UV_PATTERN="uv-aarch64*.tar.gz"
        PY_PATTERN="cpython-*aarch64*.tar.gz"
        SYSDEPS_DIR="sysdeps-arm64"
        DEPS_DIR="deps-arm64"
        # 统一 arch 名称
        HOST_ARCH="aarch64"
        ;;
    *)
        echo -e "${RED}错误: 不支持的 CPU 架构 '$HOST_ARCH'${NC}"
        echo "  支持的架构: x86_64, aarch64"
        exit 1
        ;;
esac

echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}  CapsWriter Offline v2.6 — 环境部署${NC}"
echo -e "${CYAN}  检测到架构: ${ARCH_LABEL}${NC}"
if $BOOTSTRAP; then
    echo -e "${CYAN}  模式: 完全离线 (含 Python + uv 引导安装)${NC}"
elif $OFFLINE; then
    echo -e "${CYAN}  模式: 离线 (Python 使用系统已安装版本)${NC}"
else
    echo -e "${CYAN}  模式: 在线${NC}"
fi
echo -e "${CYAN}============================================================${NC}"
echo ""

RUNTIME_DIR="$SCRIPT_DIR/runtime"
ONLINE_PIP=false  # 标记是否需要在 pip install 时联网

# 校验二进制文件是否匹配当前 CPU 架构
# 用 file 命令检查 ELF 类型：aarch64→"ARM aarch64" / x86_64→"x86-64"
validate_arch() {
    local bin_path="$1"
    if [[ ! -f "$bin_path" ]]; then
        return 1
    fi
    local file_out
    file_out=$(file "$bin_path" 2>/dev/null)
    case "$HOST_ARCH" in
        aarch64)
            echo "$file_out" | grep -qE 'ARM aarch64|aarch64' ;;
        x86_64)
            echo "$file_out" | grep -q 'x86-64' ;;
        *)
            return 0 ;;  # 未知架构不阻拦
    esac
}

# ============================================================
# Step 0: 离线引导安装 Python 和 uv (--bootstrap)
# ============================================================
if $BOOTSTRAP; then
    echo -e "${YELLOW}[0/7] 引导安装 Python 和 uv...${NC}"
    mkdir -p "$RUNTIME_DIR"

    # --- 安装 uv ---
    UV_ARCHIVE=$(ls "$SCRIPT_DIR"/$UV_PATTERN 2>/dev/null | head -1)
    if [[ -n "$UV_ARCHIVE" ]]; then
        NEED_UV_EXTRACT=false
        if [[ -x "$RUNTIME_DIR/uv" ]]; then
            if validate_arch "$RUNTIME_DIR/uv"; then
                echo "  uv 已存在 ($HOST_ARCH)，跳过"
            else
                echo -e "  ${YELLOW}⚠ uv 架构不匹配，重新解压${NC}"
                rm -f "$RUNTIME_DIR/uv" "$RUNTIME_DIR/uvx" 2>/dev/null
                NEED_UV_EXTRACT=true
            fi
        else
            NEED_UV_EXTRACT=true
        fi
        if $NEED_UV_EXTRACT; then
            echo "  解压 uv ($HOST_ARCH): $(basename "$UV_ARCHIVE")"
            tar xzf "$UV_ARCHIVE" -C "$RUNTIME_DIR" --strip-components=1 2>/dev/null || \
                tar xzf "$UV_ARCHIVE" -C "$RUNTIME_DIR" 2>/dev/null
            UV_BIN=$(find "$RUNTIME_DIR" -name uv -type f 2>/dev/null | head -1)
            if [[ -n "$UV_BIN" && "$UV_BIN" != "$RUNTIME_DIR/uv" ]]; then
                mv "$UV_BIN" "$RUNTIME_DIR/uv" 2>/dev/null || true
                UVX_BIN=$(find "$RUNTIME_DIR" -name uvx -type f 2>/dev/null | head -1)
                [[ -n "$UVX_BIN" ]] && mv "$UVX_BIN" "$RUNTIME_DIR/uvx" 2>/dev/null || true
            fi
            chmod +x "$RUNTIME_DIR/uv" 2>/dev/null || true
            if validate_arch "$RUNTIME_DIR/uv"; then
                echo -e "  ${GREEN}✓ uv 就绪 ($HOST_ARCH)${NC}"
            else
                echo -e "  ${RED}✗ uv 架构验证失败，请检查归档文件${NC}"
            fi
        fi
    else
        echo -e "  ${YELLOW}未找到 $UV_PATTERN，跳过${NC}"
    fi

    # --- 安装 Python 3.11 ---
    PY_ARCHIVE=$(ls "$SCRIPT_DIR"/$PY_PATTERN 2>/dev/null | head -1)
    if [[ -n "$PY_ARCHIVE" ]]; then
        PY_DIR="$RUNTIME_DIR/python"
        NEED_PY_EXTRACT=false
        if [[ -x "$PY_DIR/bin/python3.11" ]]; then
            if validate_arch "$PY_DIR/bin/python3.11"; then
                echo "  Python 3.11 已存在 ($HOST_ARCH)，跳过"
            else
                echo -e "  ${YELLOW}⚠ Python 架构不匹配，重新解压${NC}"
                rm -rf "$PY_DIR"
                NEED_PY_EXTRACT=true
            fi
        else
            NEED_PY_EXTRACT=true
        fi
        if $NEED_PY_EXTRACT; then
            echo "  解压 Python ($HOST_ARCH): $(basename "$PY_ARCHIVE")"
            rm -rf "$PY_DIR"
            mkdir -p "$PY_DIR"
            tar xzf "$PY_ARCHIVE" -C "$PY_DIR" --strip-components=1 2>/dev/null
            chmod +x "$PY_DIR/bin/python3.11" 2>/dev/null || true
            if validate_arch "$PY_DIR/bin/python3.11"; then
                echo -e "  ${GREEN}✓ Python 3.11 就绪 ($HOST_ARCH)${NC}"
            else
                echo -e "  ${RED}✗ Python 架构验证失败，请检查归档文件${NC}"
            fi
        fi
        PYTHON="$PY_DIR/bin/python3.11"
        export LD_LIBRARY_PATH="$PY_DIR/lib:${LD_LIBRARY_PATH:-}"
    else
        echo -e "  ${YELLOW}未找到 $PY_PATTERN，跳过${NC}"
    fi

    # --- 检查引导结果 ---
    if [[ ! -x "$PYTHON" ]]; then
        echo -e "${RED}错误: 引导安装失败，找不到 Python 3.11${NC}"
        echo "  请确保 $PY_PATTERN 在当前目录，或使用 --python 指定路径"
        exit 1
    fi
    if ! validate_arch "$PYTHON"; then
        echo -e "${RED}错误: Python 二进制与当前架构 ($HOST_ARCH) 不匹配${NC}"
        echo "  请检查 $PY_PATTERN 是否为正确的架构版本"
        exit 1
    fi
    echo ""
fi

# ============================================================
# Step 1: 检查 Python 版本
# ============================================================
echo -e "${YELLOW}[1/7] 检查 Python 版本...${NC}"

if ! command -v "$PYTHON" &>/dev/null && [[ ! -x "$PYTHON" ]]; then
    echo -e "${RED}错误: 找不到 $PYTHON${NC}"
    echo ""
    echo "  安装 Python 3.11:"
    echo "    在线: bash setup.sh"
    echo "    离线: bash setup.sh --offline --bootstrap"
    exit 1
fi

PY_VER=$("$PYTHON" --version 2>&1)
echo -e "${GREEN}  ✓ $PY_VER${NC}"
echo "  路径: $(which "$PYTHON" 2>/dev/null || realpath "$PYTHON")"

# ============================================================
# Step 2: 安装系统级依赖
# ============================================================
SYSDEPS_FULL="$SCRIPT_DIR/$SYSDEPS_DIR"

if [[ "$SKIP_SYSTEM" == true ]]; then
    echo -e "${YELLOW}[2/7] 跳过系统依赖安装${NC}"
elif [[ "$OFFLINE" == true ]] && [[ -d "$SYSDEPS_FULL" ]]; then
    echo -e "${YELLOW}[2/7] 离线安装系统依赖 ($HOST_ARCH)...${NC}"
    echo "  从 $SYSDEPS_DIR/ 安装 .deb 包..."
    if sudo dpkg -i "$SYSDEPS_FULL"/*.deb 2>&1; then
        echo -e "  ${GREEN}✓ 系统依赖安装完成${NC}"
    else
        echo -e "  ${YELLOW}⚠ 部分包安装失败，尝试修复...${NC}"
        sudo apt install -f -y 2>/dev/null || true
    fi
elif [[ "$OFFLINE" == true ]]; then
    echo -e "${YELLOW}[2/7] [离线] 未找到 $SYSDEPS_DIR/ 目录${NC}"
    echo "  请手动安装系统依赖后重新运行:"
    echo "    sudo dpkg -i $SYSDEPS_DIR/*.deb"
    echo "    sudo apt install -f -y"
    echo ""
else
    echo -e "${YELLOW}[2/7] 在线安装系统依赖...${NC}"
    SYSTEM_PKGS=(portaudio19-dev libportaudio2 libsndfile1 ffmpeg xclip)
    MISSING=()
    for pkg in "${SYSTEM_PKGS[@]}"; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            MISSING+=("$pkg")
        fi
    done
    if [[ ${#MISSING[@]} -gt 0 ]]; then
        echo "  需要安装: ${MISSING[*]}"
        sudo apt install -y "${MISSING[@]}" 2>&1 || \
            echo -e "${YELLOW}  ⚠ 安装失败，可稍后手动安装${NC}"
    else
        echo -e "${GREEN}  ✓ 系统依赖已安装${NC}"
    fi
fi

# ============================================================
# Step 3: 创建虚拟环境
# ============================================================
echo -e "${YELLOW}[3/7] 创建 Python 虚拟环境...${NC}"

VENV_DIR="$SCRIPT_DIR/.venv"

UV_BIN="$RUNTIME_DIR/uv"
if [[ -x "$UV_BIN" ]]; then
    USE_UV="$UV_BIN"
elif command -v uv &>/dev/null; then
    USE_UV="uv"
else
    USE_UV=""
fi

if [[ -d "$VENV_DIR/bin" && -f "$VENV_DIR/bin/python" ]]; then
    echo "  虚拟环境已存在，跳过创建"
else
    rm -rf "$VENV_DIR"
    if [[ -n "$USE_UV" ]]; then
        echo "  使用 uv: $USE_UV"
        $USE_UV venv --seed --python "$PYTHON" "$VENV_DIR"
    else
        "$PYTHON" -m venv --upgrade-deps "$VENV_DIR"
    fi
    echo -e "${GREEN}  ✓ 虚拟环境创建完成${NC}"
fi

source "$VENV_DIR/bin/activate"

# ============================================================
# Step 4: 安装 Python 依赖
# ============================================================
echo -e "${YELLOW}[4/7] 安装 Python 依赖...${NC}"

DEPS_FULL="$SCRIPT_DIR/$DEPS_DIR"

# 检查 deps 目录中的 wheel 架构是否匹配当前 CPU
# (x86_64 wheel 在 aarch64 上无法使用，反之亦然)
if $OFFLINE; then
    if [[ ! -d "$DEPS_FULL" ]]; then
        if [[ "$HOST_ARCH" == "aarch64" ]]; then
            echo -e "${YELLOW}  ⚠ 未找到 $DEPS_DIR/ 目录${NC}"
            echo "  ARM64 架构暂无预编译 Python 包，将切换为在线安装模式"
            echo "  (uv + Python 仍从本地离线安装)"
            echo ""
            OFFLINE=false
        else
            echo -e "${RED}错误: 离线模式需要 $DEPS_DIR/ 目录${NC}"
            exit 1
        fi
    else
        # 快速检查：deps 中是否有当前架构的 wheel
        WHEEL_COUNT=$(ls "$DEPS_FULL"/*.whl 2>/dev/null | wc -l)
        if [[ $WHEEL_COUNT -eq 0 ]]; then
            echo -e "${YELLOW}  ⚠ $DEPS_DIR/ 中无 .whl 文件${NC}"
            echo "  将切换为在线安装模式"
            OFFLINE=false
        fi
    fi
fi

if $OFFLINE; then
    echo "  从本地 $DEPS_DIR/ 离线安装 ($WHEEL_COUNT 个 wheel)"
    if [[ -n "$USE_UV" ]]; then
        $USE_UV pip install \
            --python "$VENV_DIR/bin/python" \
            --no-index \
            --find-links "$DEPS_FULL" \
            -r "$SCRIPT_DIR/requirements.txt" 2>&1 | tail -5
        RC=${PIPESTATUS[0]}
    else
        "$VENV_DIR/bin/python" -m ensurepip --upgrade 2>/dev/null || true
        "$VENV_DIR/bin/python" -m pip install --no-index --find-links="$DEPS_FULL" \
            -r "$SCRIPT_DIR/requirements.txt" 2>&1 | tail -10
        RC=${PIPESTATUS[0]}
    fi
    if [[ $RC -ne 0 ]]; then
        echo -e "${RED}  ✗ 离线安装失败 (exit $RC)${NC}"
        echo "  可能原因:"
        echo "    1. $DEPS_DIR/ 中 wheel 架构与当前 CPU 不匹配"
        echo "    2. $DEPS_DIR/ 文件不完整"
        echo "  尝试: bash setup.sh  (在线模式)"
        exit $RC
    fi
else
    echo "  在线安装 Python 依赖..."
    # 确保有 C 编译器用于构建 evdev/srt 等源码包
    # Python build-standalone 默认使用 clang，若不存在则用 gcc
    if ! command -v clang &>/dev/null && command -v gcc &>/dev/null; then
        export CC=gcc
        echo "  (clang 未安装，使用 gcc 编译)"
    fi
    if [[ -n "$USE_UV" ]]; then
        $USE_UV pip install -r "$SCRIPT_DIR/requirements.txt"
        RC=$?
    else
        pip install -r "$SCRIPT_DIR/requirements.txt"
        RC=$?
    fi
    if [[ $RC -ne 0 ]]; then
        echo -e "${RED}  ✗ 在线安装失败 (exit $RC)${NC}"
        echo "  可能原因:"
        echo "    1. 网络连接问题"
        echo "    2. 缺少 C 编译器 (apt install clang 或 gcc)"
        echo "    3. 部分包在当前架构上不可用"
        echo "  尝试: apt install clang -y && bash setup.sh --bootstrap"
        exit $RC
    fi
fi
echo -e "${GREEN}  ✓ Python 依赖安装完成${NC}"

# ============================================================
# Step 5: 验证关键模块
# ============================================================
echo -e "${YELLOW}[5/7] 验证关键模块...${NC}"

MODULES=(
    "numpy" "sounddevice" "websockets" "rich"
    "onnxruntime" "soundfile" "sentencepiece" "rapidfuzz"
)

FAILED=()
for mod in "${MODULES[@]}"; do
    if python -c "import $mod" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $mod"
    else
        echo -e "  ${RED}✗${NC} $mod"
        FAILED+=("$mod")
    fi
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo -e "${RED}以下模块导入失败: ${FAILED[*]}${NC}"
    exit 1
fi

# ============================================================
# Step 6: 验证模型文件
# ============================================================
echo -e "${YELLOW}[6/7] 验证模型文件...${NC}"

MODEL_DIR="$SCRIPT_DIR/models"
CURRENT_MODEL=$(grep "model_type" "$SCRIPT_DIR/config_server.py" 2>/dev/null | grep -v "^#" | grep -oP "'\K[^']*" | head -1)

echo "  当前引擎: ${CURRENT_MODEL:-未知}"

case "$CURRENT_MODEL" in
    sensevoice)
        # 模型目录可能有两种命名: Sensevoice-Small-ONNX 或 SenseVoice-Small
        if [[ -d "$MODEL_DIR/Sensevoice-Small-ONNX" ]]; then
            SV_DIR="$MODEL_DIR/Sensevoice-Small-ONNX"
        elif [[ -d "$MODEL_DIR/SenseVoice-Small" ]]; then
            SV_DIR="$MODEL_DIR/SenseVoice-Small"
        else
            SV_DIR="$MODEL_DIR/Sensevoice-Small-ONNX"
        fi
        CHECK_FILES=(
            "$SV_DIR/SenseVoice-Encoder.fp16.onnx"
            "$SV_DIR/SenseVoice-CTC.fp16.onnx"
            "$SV_DIR/tokenizer.bpe.model"
        )
        ;;
    paraformer)
        CHECK_FILES=(
            "$MODEL_DIR/Paraformer/speech_paraformer-large-vad-punc_asr_nat-zh-cn-16k-common-vocab8404-onnx/model.onnx"
            "$MODEL_DIR/Paraformer/speech_paraformer-large-vad-punc_asr_nat-zh-cn-16k-common-vocab8404-onnx/tokens.txt"
        )
        ;;
    fun_asr_nano)
        CHECK_FILES=(
            "$MODEL_DIR/Fun-ASR-Nano/Fun-ASR-Nano-Encoder-Adaptor.fp16.onnx"
            "$MODEL_DIR/Fun-ASR-Nano/Fun-ASR-Nano-CTC.fp16.onnx"
            "$MODEL_DIR/Fun-ASR-Nano/Fun-ASR-Nano-Decoder.q5_k.gguf"
            "$MODEL_DIR/Fun-ASR-Nano/tokens.txt"
        )
        ;;
    *)
        echo -e "  ${YELLOW}未知引擎类型，跳过模型验证${NC}"
        CHECK_FILES=()
        ;;
esac

MODEL_OK=true
for f in "${CHECK_FILES[@]}"; do
    if [[ -f "$f" ]]; then
        SIZE=$(du -h "$f" | cut -f1)
        echo -e "  ${GREEN}✓${NC} $(basename "$f") ($SIZE)"
    else
        echo -e "  ${RED}✗${NC} 缺失: $f"
        MODEL_OK=false
    fi
done

if ! $MODEL_OK; then
    echo ""
    echo -e "${RED}模型文件缺失!${NC}"
    echo "  下载: https://github.com/HaujetZhao/CapsWriter-Offline/releases/tag/models"
    exit 1
fi

# ============================================================
# Step 7: 启动脚本权限
# ============================================================
echo -e "${YELLOW}[7/7] 准备启动脚本...${NC}"
for script in start_server.sh start_client.sh test_mic.sh; do
    [[ -f "$SCRIPT_DIR/$script" ]] && chmod +x "$SCRIPT_DIR/$script"
done
echo -e "${GREEN}  ✓ 启动脚本就绪${NC}"

# ============================================================
# 完成
# ============================================================
echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${GREEN}  部署完成!  架构: ${ARCH_LABEL}${NC}"
echo ""
echo "  启动服务端:  bash start_server.sh"
echo "  启动客户端:  bash start_client.sh"
echo "  测试麦克风:  bash test_mic.sh"
echo ""
echo "  详细文档:    docs/Ubuntu离线部署教程.md"
echo -e "${CYAN}============================================================${NC}"
