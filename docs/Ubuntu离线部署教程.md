# CapsWriter Offline v2.6 — Ubuntu 离线部署教程

## 一、项目概览

CapsWriter Offline 是客户端-服务端架构的离线语音转文字工具，支持 **x86_64 (amd64)** 和 **aarch64 (arm64)** 两种 CPU 架构。

```
┌──────────────┐    WebSocket     ┌──────────────┐
│  Client      │ ◄──────────────► │  Server      │
│  (麦克风/文件) │   AudioMessage   │  (ASR 引擎)   │
│  Python 3.11 │   RecognitionMsg │  Python 3.11 │
│  + sounddevice│                 │  + onnxruntime│
└──────────────┘                  └──────────────┘
```

- **服务端**：ASR 引擎（SenseVoice / Paraformer / Fun-ASR-Nano / Qwen3-ASR），纯 CPU 推理
- **客户端**：16kHz 麦克风直采、快捷键监听（F7/F8）、文本输出、文件转录
- **通信协议**：JSON + WebSocket，音频为 base64 编码的 float32 16kHz mono PCM

---

## 二、环境要求

| 组件 | 要求 | 说明 |
|------|------|------|
| 操作系统 | Ubuntu 20.04+ / Kylin V10 | 支持 x86_64 和 aarch64 |
| Python | 3.11+（项目自带离线安装包） | 完全离线无需预装 |
| RAM | 4GB+ | SenseVoice 约需 2GB |
| 磁盘 | 1GB+（仅 SenseVoice 模型） | 含全部 6 套模型则需 6.5GB |

---

## 三、架构支持与部署模式

`setup.sh` 通过 `uname -m` 自动识别 CPU 架构，选择对应的离线安装包。

| 架构 | `uname -m` | Python 归档 | uv 归档 | 系统依赖 | Python 包 |
|------|-----------|------------|---------|---------|----------|
| x86_64 | `x86_64` | `cpython-*x86_64*.tar.gz` | `uv-x86_64*.tar.gz` | `sysdeps/` | `deps/` (54 个 wheel) |
| aarch64 | `aarch64` | `cpython-*aarch64*.tar.gz` | `uv-aarch64*.tar.gz` | `sysdeps-arm64/` | `deps-arm64/` (54 个 wheel) |

> **两种架构的离线包均已就绪**，无需网络即可完成全部部署。

### 部署模式速查

| 场景 | 命令 |
|------|------|
| x86_64 在线 | `bash setup.sh` |
| x86_64 完全离线 | `bash setup.sh --offline --bootstrap` |
| ARM64 在线 | `bash setup.sh --bootstrap` |
| ARM64 完全离线 | `bash setup.sh --offline --bootstrap` |
| 跳过系统依赖 | 追加 `--skip-system` |

---

## 四、项目文件结构

```
CapsWriter-Offline-v2.6/
├── config_client.py          # 客户端配置（快捷键、录音参数等）
├── config_server.py          # 服务端配置（引擎选择、模型路径等）
├── requirements.txt          # Python 依赖列表
├── setup.sh                  # ★ 多架构一键部署脚本
├── start_server.sh           # 启动服务端
├── start_client.sh           # 启动客户端（支持传文件路径）
├── test_mic.py / test_mic.sh # 麦克风测试
├── hot.txt / hot-rule.txt    # 客户端热词（音素 RAG + 正则）
├── hot-server.txt            # 服务端热词（直接传给 ASR 引擎）
│
├── ★ 离线安装包（两种架构均已就绪）:
│   ├── cpython-3.11.15+20260504-x86_64-install_only.tar.gz  (47MB)
│   ├── cpython-3.11.15+20260504-aarch64-install_only.tar.gz (47MB)
│   ├── uv-x86_64-unknown-linux-gnu.tar.gz                   (24MB)
│   ├── uv-aarch64-unknown-linux-gnu.tar.gz                  (22MB)
│   ├── sysdeps/              # x86_64 系统 .deb (6 个, 1.9MB)
│   ├── sysdeps-arm64/        # ARM64 系统 .deb (6 个, 1.9MB)
│   ├── deps/                 # x86_64 Python wheel (55 个, ~75MB)
│   └── deps-arm64/           # ARM64 Python wheel (55 个, ~70MB)
│
├── runtime/                  # 部署后生成: Python + uv 运行环境
├── .venv/                    # 部署后生成: Python 虚拟环境
│
├── models/                   # ★ ASR 模型文件（架构无关，ONNX/GGUF 可跨平台复用）
│   ├── SenseVoice-Small/     # 452MB — 默认引擎，✅ 已就绪
│   │   ├── SenseVoice-Encoder.fp16.onnx  (427MB)
│   │   ├── SenseVoice-CTC.fp16.onnx      (25MB)
│   │   └── tokenizer.bpe.model           (369KB)
│   ├── Fun-ASR-Nano/         # ⚠️ 需下载 (~1.5GB)
│   ├── Paraformer/           # ⚠️ 需下载 (~1.0GB)
│   ├── Qwen3-ASR/            # ⚠️ 需下载 (~2.7GB，推荐追求最高准确率)
│   ├── Qwen3-ForcedAligner/  # ⚠️ 需下载（Qwen3-ASR 生成精确时间戳时需要）
│   └── Punct-CT-Transformer/ # 无需下载 — SenseVoice 自带标点
│
├── core/                     # 源码
├── LLM/                      # LLM 角色配置
└── docs/                     # 文档
```

---

## 五、快速部署

### 5.1 x86_64 (amd64)

```bash
cd CapsWriter-Offline-v2.6

# 在线
bash setup.sh

# 完全离线
bash setup.sh --offline --bootstrap

# 启动
bash start_server.sh    # 终端1
bash start_client.sh    # 终端2
```

### 5.2 ARM64 (aarch64) — Kylin V10 飞腾/鲲鹏

```bash
cd CapsWriter-Offline-v2.6

# 完全离线（推荐，所有包已就绪）
bash setup.sh --offline --bootstrap

# 在线（如离线失败可尝试）
bash setup.sh --bootstrap

# 启动
bash start_server.sh    # 终端1
bash start_client.sh    # 终端2
```

> **注意**：`setup.sh` 会自动检测系统 C 编译器情况（`clang` / `gcc`），若 `clang` 未安装会自动设置 `CC=gcc`。所有依赖包的 wheel 已预编译，正常情况下无需编译器。

---

## 六、文件转录

支持将音视频文件转录为 SRT 字幕和 TXT 文本。

```bash
# 终端1 — 启动服务端
bash start_server.sh

# 终端2 — 转录单个文件
bash start_client.sh demo.mp3

# 批量转录
bash start_client.sh file1.mp3 file2.wav file3.flac
```

转录结果保存在同目录：`<文件名>.srt`、`<文件名>.txt` 和 `<文件名>.json`。

---

### 6.1 要求

系统需安装 FFmpeg（`sysdeps/` 已包含，`setup.sh` 会自动安装）。

验证: `ffmpeg -version`。

---

### 6.2 输出文件说明

| 文件 | 内容 | 用途 |
|------|------|------|
| `.srt` | SRT 字幕，时间轴精确到句 | 视频剪辑软件导入 |
| `.txt` | 按标点分行的纯文本 | 阅读、校对 |
| `.json` | 字级时间戳 | 手动修正字幕时使用 |
| `.merge.txt` | 未切分的整段文本 | 默认不生成，可在 `config_client.py` 中开启 |

### 6.3 手动修正字幕

如果识别结果有错字，或想调整分行：

1. 编辑生成的 `.txt` 文件，修改错字、调整分行
2. 将修改后的 `.txt` 文件**重新拖拽**到客户端（或作为命令行参数传入）
3. 客户端会利用 `.json` 中的字级时间戳，与修改后的文本重新对齐，生成新的 `.srt` 文件

> **依赖说明**: 此功能依赖 `srt` Python 包（`requirements.txt` 已包含）。如果报 `ModuleNotFoundError: No module named 'srt'`，运行 `source .venv/bin/activate && pip install srt`。

### 6.4 提高歌曲/音乐转录准确率

ASR 模型是为**语音**设计的，对**歌曲**（人声+乐器混合）的准确率天然受限。推荐的解决方案：

1. **人声分离预处理**（效果最好）: 使用人声分离工具将人声从乐器中提取出来，再对纯人声进行转录

   ```bash
   # 使用 Demucs (Meta 开发，pip install demucs)
   demucs --two-stems=vocals song.mp3
   # 输出: separated/htdemucs/song/vocals.wav
   bash start_client.sh separated/htdemucs/song/vocals.wav
   
   # 或使用 UVR (Ultimate Vocal Remover)
   # https://github.com/Anjok07/ultimatevocalremovergui
   ```

2. **切换到更强的模型**: Qwen3-ASR 比 SenseVoice-Small 准确率高很多（见第十节引擎对比）

3. **提高音频质量**: 优先使用原始 WAV/FLAC 格式，避免 128kbps 等低码率 MP3

---

## 七、离线部署包制作（联网机器上准备）

### 7.1 x86_64 离线包制作

```bash
cd CapsWriter-Offline-v2.6

# 1. 下载 Python 3.11 独立安装包
#    https://github.com/astral-sh/python-build-standalone/releases
#    → cpython-3.11.*-x86_64-unknown-linux-gnu-install_only.tar.gz

# 2. 下载 uv
#    https://github.com/astral-sh/uv/releases
#    → uv-x86_64-unknown-linux-gnu.tar.gz

# 3. 下载系统 .deb
mkdir -p sysdeps && cd sysdeps
apt download portaudio19-dev libportaudio2 libsndfile1 ffmpeg xclip xdotool
cd ..

# 4. 制作 Python 包离线源
uv venv --python 3.11 .venv && source .venv/bin/activate
uv pip install -r requirements.txt
mkdir -p deps
pip download -r requirements.txt -d deps/
# 预编译 evdev 和 srt（注意要设置 CC=gcc）
CC=gcc pip wheel --wheel-dir deps/ evdev srt
rm -f deps/evdev-*.tar.gz deps/srt-*.tar.gz

# 5. 验证
bash setup.sh --offline --bootstrap --skip-system   # 应 7/7 全部通过

# 6. 打包
cd .. && tar -czf capswriter-offline-v2.6-x86_64.tar.gz CapsWriter-Offline-v2.6/
```

### 7.2 ARM64 离线包制作

在**联网的 ARM64 机器**（如飞腾 FT-2000、鲲鹏 920）上执行：

```bash
cd CapsWriter-Offline-v2.6

# 1-3. 同上，下载 ARM64 版本的 Python、uv、系统 .deb
#   Python: cpython-*aarch64*-install_only.tar.gz
#   uv:     uv-aarch64-unknown-linux-gnu.tar.gz
#   .deb:   mkdir -p sysdeps-arm64 && cd sysdeps-arm64
#           apt download portaudio19-dev libportaudio2 libsndfile1 ffmpeg xclip xdotool

# 4. ★ 制作 ARM64 专用 Python 包离线源
bash setup.sh --bootstrap          # 先用本地 Python+uv 在线安装
source .venv/bin/activate
mkdir -p deps-arm64
pip download -r requirements.txt -d deps-arm64/
# 预编译 evdev 和 srt（注意要设置 CC=gcc）
CC=gcc pip wheel --wheel-dir deps-arm64/ evdev srt
rm -f deps-arm64/evdev-*.tar.gz deps-arm64/srt-*.tar.gz

# 5. 验证
bash setup.sh --offline --bootstrap --skip-system   # 应 7/7 全部通过

# 6. 打包
cd .. && tar -czf capswriter-offline-v2.6-aarch64.tar.gz CapsWriter-Offline-v2.6/
```

> 在 x86_64 机器上无法制作 ARM64 的 `deps-arm64/`（`pip download` 默认下载当前架构的 wheel）。必须用 ARM64 机器或 QEMU 模拟环境。

---

## 八、部署到离线目标机

### 8.1 x86_64 目标机

```bash
tar -xzf capswriter-offline-v2.6-x86_64.tar.gz -C ~/
cd ~/CapsWriter-Offline-v2.6

sudo dpkg -i sysdeps/*.deb 2>/dev/null
sudo apt install -f -y

bash setup.sh --offline --bootstrap
bash start_server.sh && bash start_client.sh
```

### 8.2 ARM64 目标机

```bash
tar -xzf capswriter-offline-v2.6-aarch64.tar.gz -C ~/
cd ~/CapsWriter-Offline-v2.6

sudo dpkg -i sysdeps-arm64/*.deb 2>/dev/null
sudo apt install -f -y

bash setup.sh --offline --bootstrap
bash start_server.sh && bash start_client.sh
```

---

## 九、离线部署包清单

### 架构无关（两种架构共用）

| 组件 | 路径 | 大小 | 说明 |
|------|------|------|------|
| ASR 模型 | `models/SenseVoice-Small/` | 452MB | **默认引擎，已就绪** |
| 配置文件 | `config_*.py`, `requirements.txt` | — | |
| 源码 | `core/`, `LLM/` | — | |
| 热词 | `hot*.txt` | — | |

### x86_64 专用

| 组件 | 文件 | 大小 |
|------|------|------|
| Python 3.11 | `cpython-*x86_64*-install_only.tar.gz` | 47MB |
| uv 包管理器 | `uv-x86_64-*.tar.gz` | 24MB |
| 系统依赖 | `sysdeps/` (6 个 .deb) | 1.9MB |
| Python 包 | `deps/` (55 个 wheel) | ~75MB |
| **x86_64 合计** | | **~148MB + 452MB 模型** |

### ARM64 专用

| 组件 | 文件 | 大小 |
|------|------|------|
| Python 3.11 | `cpython-*aarch64*-install_only.tar.gz` | 47MB |
| uv 包管理器 | `uv-aarch64-*.tar.gz` | 22MB |
| 系统依赖 | `sysdeps-arm64/` (6 个 .deb) | 1.9MB |
| Python 包 | `deps-arm64/` (55 个 wheel) | ~70MB |
| **ARM64 合计** | | **~141MB + 452MB 模型** |

### 离线包校验

```bash
# 验证 Python/uv 归档架构正确
file <(tar xzOf cpython-*-aarch64*-install_only.tar.gz --wildcards '*/bin/python3.11')
# 应输出: ARM aarch64

# 验证 deps 包数量（两种架构各 55 个）
ls deps/*.whl | wc -l        # x86_64
ls deps-arm64/*.whl | wc -l  # arm64

# 验证 deps 包架构
ls deps/*.whl | grep -v 'none-any' | while read f; do
    echo "$f" | grep -q "x86_64" || echo "架构异常: $f"
done
```

---

## 十、模型与引擎配置

编辑 `config_server.py`（与架构无关）：

```python
class ServerConfig:
    model_type = 'sensevoice'    # 引擎选择，见下表
    enable_tray = False          # Linux 下禁用托盘
```

### 引擎对比

| 模型 | `model_type` | 准确率 | CPU 速度 | 内存 | 自带标点 | 模型大小 | 当前状态 |
|------|:---:|--------|---------|------|:---:|------|------|
| SenseVoice | `sensevoice` | ★★★☆☆ | 基线 (0.6s) | ~2GB | ✅ 是 | 452MB | **✅ 已就绪** |
| Fun-ASR-Nano | `fun_asr_nano` | ★★★★☆ | ~3× (2.0s) | ~3GB | ✅ 是 | ~1.5GB | ⚠️ 需下载 |
| Paraformer | `paraformer` | ★★★☆☆ | ~1× (0.6s) | ~1.5GB | ❌ 否 | ~1.0GB | ⚠️ 需下载 |
| Qwen3-ASR | `qwen_asr` | ★★★★★ | ~6× (4.0s) | ~4GB | ✅ 是 | ~2.7GB | ⚠️ 需下载 |

> **推荐路径**: 默认 `sensevoice` 可用即用 → 追求准确率用 `qwen_asr` → 平衡速度与准确率用 `fun_asr_nano`。

### 关于标点符号

- **SenseVoice、Fun-ASR-Nano、Qwen3-ASR 自带标点**：模型原生输出带标点符号的文本，无需额外标点模型
- **Paraformer 不带标点**：若使用 Paraformer，需额外下载 `Punct-CT-Transformer` 标点模型（约 300MB）
- 默认引擎 SenseVoice 已包含标点能力，`Punct-CT-Transformer/` 目录无需关注

### 下载其他引擎模型

模型发布页: https://github.com/HaujetZhao/CapsWriter-Offline/releases/tag/models

各引擎所需模型文件清单:

**Qwen3-ASR 1.7B** (推荐，准确率最高)
```
models/Qwen3-ASR/Qwen3-ASR-1.7B/
├── qwen3_asr_encoder_frontend.onnx
├── qwen3_asr_encoder_backend.onnx
└── qwen3_asr_llm.gguf          # 约 2.3GB
```
> Qwen3-ASR 生成精确时间戳还需 ForceAligner 模型（`models/Qwen3-ForcedAligner/`）

**Fun-ASR-Nano**
```
models/Fun-ASR-Nano/Fun-ASR-Nano-GGUF/
├── Fun-ASR-Nano-Encoder-Adaptor.fp16.onnx
├── Fun-ASR-Nano-CTC.fp16.onnx
├── Fun-ASR-Nano-Decoder.q5_k.gguf
└── tokens.txt
```

**Paraformer** (不带标点，需同时下载 `Punct-CT-Transformer/`)
```
models/Paraformer/speech_paraformer-large-vad-punc_asr_nat-zh-cn-16k-common-vocab8404-onnx/
├── model.onnx
└── tokens.txt
```

下载后修改 `config_server.py` 的 `model_type` 后重启服务端。

> **模型文件为架构无关格式** (ONNX/GGUF)。在 arm64 机器上下载的模型文件可直接复制到 x86_64 机器使用，无需重新下载。

---

## 十一、setup.sh 选项参考

```
用法: bash setup.sh [选项]

选项:
  --offline       离线模式，从本地 deps/ 或 deps-arm64/ 安装 Python 包
  --bootstrap     从本地归档引导安装 Python + uv
  --skip-system   跳过系统级依赖安装
  --python PATH   指定 Python 解释器路径

架构自动检测:
  setup.sh 通过 uname -m 自动识别 x86_64 / aarch64，
  并选择对应架构的归档文件和系统依赖目录。

运行时校验:
  setup.sh 通过 file 命令验证 runtime/ 中二进制文件的 CPU 架构。
  如果残留了错误架构的二进制（如 x86-64 在 ARM 机器上），
  脚本会自动检测并重新解压。
```

---

## 十二、ARM64 部署注意事项

1. **离线包已就绪**：`deps-arm64/` 已包含 54 个 aarch64 wheel，可直接离线部署无需联网
2. **C 编译器**：离线包中已包含预编译的 `evdev` wheel。在线安装时 `setup.sh` 会自动选择可用编译器（clang 或 gcc）
3. **运行时架构校验**：`setup.sh` 会验证 `runtime/` 中二进制架构，防止错误架构残留
4. **模型目录命名**：`setup.sh` 自动检测 `SenseVoice-Small` 和 `Sensevoice-Small-ONNX` 两种命名
5. **性能**：ARM64 SenseVoice ONNX 推理性能与同频率 x86_64 相当
6. **Kylin V10**：`sysdeps-arm64/` 中 .deb 已适配 Kylin 仓库版本
7. **页面大小**：部分 ARM64 系统使用 64KB 页面大小。如遇到 `libpython3.11.so` 加载失败，检查 `LD_LIBRARY_PATH` 是否指向 `runtime/python/lib`

---

## 十三、快捷键配置

编辑 `config_client.py`：

```python
shortcuts = [
    # F7 — 长按模式：按住说话，松开输入
    {'key': 'f7',  'type': 'keyboard',
     'suppress': True, 'hold_mode': True,  'enabled': True},

    # F8 — 单击切换模式：按一次开始，再按一次停止
    {'key': 'f8',  'type': 'keyboard',
     'suppress': True, 'hold_mode': False, 'enabled': True},

    # 鼠标侧键 X2（ARM64 可能不可用，默认禁用）
    {'key': 'x2',  'type': 'mouse',
     'suppress': True, 'hold_mode': True,  'enabled': False},
]

threshold = 0.3              # 长按判定阈值 (秒)
paste = True                 # 粘贴模式（推荐）
language = 'auto'            # 'auto' / 'chinese' / 'english'
mic_seg_duration = 60        # 分段时长 (秒)
enable_tray = False          # Linux 下关闭托盘
```

---

## 十四、常见故障

### Q1: 离线安装 Python 包失败

```bash
# 确认 deps/ 中 wheel 架构与当前 CPU 匹配
ls deps/ | grep -v 'none-any' | while read f; do echo "$f" | grep -q "x86_64" || echo "异常: $f"; done

# 确认 deps/ 文件数正确
ls deps/*.whl | wc -l   # 应为 54

# 手动离线安装
source .venv/bin/activate
pip install --no-index --find-links=deps/ -r requirements.txt
```

### Q2: "可执行文件格式错误" (runtime Python 无法运行)

```bash
# 验证 runtime Python 架构是否匹配
file runtime/python/bin/python3.11
# x86_64 机器应显示: x86-64
# ARM64 机器应显示: ARM aarch64

# 如不匹配，删除 runtime/ 重新运行
rm -rf runtime/
bash setup.sh --bootstrap
```

### Q3: ARM64 运行时 `libpython3.11.so` 加载失败

```bash
export LD_LIBRARY_PATH=$PWD/runtime/python/lib:$LD_LIBRARY_PATH
```

### Q4: pynput 无法捕获按键

```bash
echo $XDG_SESSION_TYPE   # 必须为 x11
# Wayland → 切换到 Xorg 登录
```

### Q5: evdev 编译失败 (`command 'clang' failed`)

`setup.sh` 已自动处理：若 `clang` 未安装会自动设置 `CC=gcc`。也可手动指定：

```bash
CC=gcc bash setup.sh --bootstrap
# 或安装 clang
sudo apt install clang -y
```

### Q6: 模型文件缺失

```bash
# 创建模型目录软链接（解决命名差异）
cd models && ln -sf SenseVoice-Small Sensevoice-Small-ONNX

# 验证
ls models/Sensevoice-Small-ONNX/SenseVoice-*.onnx
```

### Q7: 文件转录报 `ModuleNotFoundError: No module named 'typer'`

```bash
# 完整错误: ModuleNotFoundError: No module named 'typer' (或 'rich' / 'srt')
# 原因: Python 依赖安装不完整

# 解决方法 — 在线补装缺失的包:
source .venv/bin/activate
pip install -r requirements.txt

# 离线环境 — 从本地 deps 补装:
source .venv/bin/activate
pip install --no-index --find-links=deps/ -r requirements.txt

# 验证修复:
python -c "from core.client.transcribe.result_handler import ResultHandler; print('OK')"
```

> **技术说明**: `core/tools/srt_from_txt.py` 是一个独立 CLI 工具，它在模块顶部导入了 `typer`、`srt`、`rich`。当 `result_handler.py` 导入 `srt_from_txt` 模块时，这些依赖会被触发加载。v2.6 已修复了这个问题——将 `typer` 改为延迟导入（仅在 `__main__` 模式时加载），`rich` 改为 fallback 导入，并在 `requirements.txt` 中包含了 `srt` 作为运行时依赖。

### Q8: 转录结果准确率极差（歌曲/音乐/嘈杂音频）

症状: 转录出来的文字严重错乱，几乎不可读（例如歌曲转录输出大白话）。

**主要原因**:

1. **ASR 模型是为语音设计的**，不是唱歌。乐器伴奏对模型而言等同于噪声。
2. **SenseVoice-Small 是轻量模型**（427MB 编码器），对复杂音频的鲁棒性有限。

**解决方案（按有效性排序）**:

1. **人声分离预处理**（对歌曲效果最好）:
   ```bash
   # Demucs (Meta 开发)
   pip install demucs
   demucs --two-stems=vocals song.mp3
   bash start_client.sh separated/htdemucs/song/vocals.wav
   ```

2. **切换到 Qwen3-ASR 引擎**（准确率大幅提升）:
   下载 Qwen3-ASR 模型后，在 `config_server.py` 中设置 `model_type = 'qwen_asr'`

3. **提高音频质量**: 优先使用原始 WAV/FLAC，避免低码率 MP3

4. **用纯语音内容验证**: 先用一段清晰的语音（播客、演讲）测试，确认系统本身工作正常

### Q9: 端口 6016 冲突

```bash
ss -tlnp | grep 6016
kill <PID>
```

### Q10: 文件转录报 "未检测到 FFmpeg"

```bash
# 离线安装（sysdeps 中已包含）
sudo dpkg -i sysdeps-arm64/ffmpeg_*.deb 2>/dev/null
sudo apt install -f -y

# 在线安装
sudo apt install ffmpeg -y
```

---

## 十五、开机自启（systemd）

```bash
mkdir -p ~/.config/systemd/user/

# 服务端
cat > ~/.config/systemd/user/capswriter-server.service << 'EOF'
[Unit]
Description=CapsWriter ASR Server
After=default.target
[Service]
Type=simple
WorkingDirectory=%h/CapsWriter-Offline-v2.6
Environment=LD_LIBRARY_PATH=%h/CapsWriter-Offline-v2.6/runtime/python/lib
ExecStart=%h/CapsWriter-Offline-v2.6/.venv/bin/python -m core.server.app
Restart=on-failure
RestartSec=5
[Install]
WantedBy=default.target
EOF

# 客户端
cat > ~/.config/systemd/user/capswriter-client.service << 'EOF'
[Unit]
Description=CapsWriter Client
After=capswriter-server.service
BindsTo=capswriter-server.service
[Service]
Type=simple
WorkingDirectory=%h/CapsWriter-Offline-v2.6
Environment=LD_LIBRARY_PATH=%h/CapsWriter-Offline-v2.6/runtime/python/lib
ExecStart=%h/CapsWriter-Offline-v2.6/.venv/bin/python -m core.client.app
Restart=on-failure
RestartSec=3
[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable capswriter-server capswriter-client
sudo loginctl enable-linger $USER
```
