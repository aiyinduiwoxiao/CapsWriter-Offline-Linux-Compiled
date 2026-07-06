# CapsWriter Offline v2.6 — Linux 编译版

本项目基于以下两个来源修改：

- **原项目**: [HaujetZhao/CapsWriter-Offline](https://github.com/HaujetZhao/CapsWriter-Offline) v2.6 — 作者 [Haujet Zhao](https://github.com/HaujetZhao)
- **Linux 适配版**: [new985211/CapsWriter-Offline](https://github.com/new985211/CapsWriter-Offline) 发布的 v2.6-Linux release

### 本仓库额外修改
- 修复 llama.cpp b9881 下 `llama_context_params` 结构体缺失字段导致 `llama_init_from_model` 段错误
- 修复 `inference/__init__.py` 中 `try` 导入损坏导致 CWD 被意外修改的问题
- 集成预编译 llama.cpp b9881 Linux x86_64 库（免去自行编译）
- 预置 SenseVoice-Small（GGUF）、SenseVoice-Small-ONNX、Paraformer 模型

CapsWriter Offline 是一个**客户端-服务端架构**的离线语音识别工具。支持**麦克风实时录入**和**音视频文件转录**，无需网络。

```
┌──────────────┐    WebSocket     ┌──────────────┐
│  Client      │ ◄──────────────► │  Server      │
│  (录音/快捷键) │   AudioMessage   │  (ASR 推理)   │
│  Python 3.11 │   RecognitionMsg │  Python 3.11 │
└──────────────┘                  └──────────────┘
```

- **服务端**: 纯 CPU ONNX/GGUF 推理，支持 4 种 ASR 引擎
- **客户端**: 麦克风录音、快捷键监听、文件转录、热词替换、LLM 后处理
- **通信**: WebSocket + JSON，音频为 base64 float32 16kHz mono PCM

---

## 架构支持

| 架构 | 平台 | 状态 |
|------|------|------|
| x86_64 (amd64) | Intel/AMD Linux | ✅ 完整支持 |
| aarch64 (arm64) | 飞腾/鲲鹏/树莓派 Linux | ✅ 完整支持 |

`setup.sh` 通过 `uname -m` 自动识别 CPU 架构，选择对应的离线安装包。

---

## 快速开始

> ⚠️ **本仓库不包含模型文件**。克隆后需先下载模型（见下方说明），否则 `start_server.sh` 会提示模型检查不通过。

### 环境要求

- **操作系统**: Ubuntu 20.04+ / Kylin V10 / Debian 11+
- **Python**: 3.11（项目自带离线安装包，无需预装）
- **RAM**: 4GB+（SenseVoice 约需 2GB）
- **磁盘**: 1GB+（SenseVoice 模型 452MB + Python 环境约 600MB）
- **系统依赖**: ffmpeg、portaudio、libsndfile（`setup.sh` 自动安装）

### 一键部署

```bash
cd CapsWriter-Offline-v2.6

# x86_64 在线部署
bash setup.sh

# ARM64 / x86_64 完全离线部署（所有安装包已就绪）
bash setup.sh --offline --bootstrap

# 跳过系统级依赖（如已有 root 权限安装过）
bash setup.sh --offline --bootstrap --skip-system
```

`setup.sh` 自动执行 7 步：检查 Python → 安装系统依赖 → 创建虚拟环境 → 安装 Python 包 → 验证关键模块 → 验证模型文件 → 准备启动脚本。

### 启动

```bash
bash start_server.sh    # 终端 1 — 启动 ASR 服务端
bash start_client.sh    # 终端 2 — 启动客户端（麦克风模式）
```

---

## 文件转录

将音视频文件转为 SRT 字幕和 TXT 文本，支持批量处理。

```bash
# 转录单个文件
bash start_client.sh demo.mp3

# 批量转录
bash start_client.sh file1.mp3 file2.wav file3.flac
```

### 输出文件

| 文件 | 内容 | 默认 |
|------|------|:---:|
| `<文件名>.srt` | SRT 字幕，时间轴精确到句 | ✅ |
| `<文件名>.txt` | 按标点分行的纯文本 | ✅ |
| `<文件名>.json` | 字级时间戳 | ✅ |
| `<文件名>.merge.txt` | 未切分的整段文本 | ❌ |

支持格式: mp3, wav, aac, flac, ogg, mp4, mkv, flv, avi, mov 等（需 ffmpeg 解码非 WAV 格式）。

> **视频提取音频**: 建议先提取音频再转录，避免视频流干扰。
> ```bash
# 基本用法：提取所有音轨为 MP3（录播视频原编码常为 AAC，转 MP3 体积更小）
ffmpeg -i input.mp4 -q:a 2 output.mp3

# 保留原 AAC 编码（无损、快速、不重编码，仅解封装）
ffmpeg -i input.mp4 -c:a copy output.aac

# 推荐 ASR 格式：WAV 16kHz 单声道（ffmpeg 自动重编码）
ffmpeg -i input.mp4 -ar 16000 -ac 1 output.wav
# ```
>
> **多音轨视频**: 如录制视频同时有麦克风音轨和系统音轨，先用 `ffprobe` 查看音轨列表，再用 `-map` 指定所需音轨：
> ```bash
ffprobe input.mp4                    # 查看所有音轨
ffmpeg -i input.mp4 -map 0:a:1 -ar 16000 -ac 1 output.wav   # 提取第2条音轨
# ```
>
> 提取后对独立音频文件运行 `bash start_client.sh output.wav` 转录即可。

### 手动修正字幕

1. 编辑生成的 `.txt` 文件（改错字、调分行）
2. 将修改后的 `.txt` 拖拽到客户端（或作为参数传入）
3. 客户端会利用 `.json` 中的字级时间戳与修改后的文本重新对齐，生成新的 `.srt`

---

## ASR 引擎选择

编辑 `config_server.py` 切换引擎:

```python
class ServerConfig:
    model_type = 'sensevoice'    # 可选: 'sensevoice', 'fun_asr_nano', 'qwen_asr', 'paraformer'
```

### 引擎对比

| 引擎 | `model_type` | 准确率 | CPU 速度 | 内存 | 自带标点 | 模型大小 |
|------|:---:|:---:|:---:|:---:|:---:|:---:|
| Qwen3-ASR 1.7B | `qwen_asr` | ★★★★★ | ~4× | ~4GB | ✅ | ~2.7GB |
| Fun-ASR-Nano | `fun_asr_nano` | ★★★★☆ | ~3× | ~3GB | ✅ | ~1.5GB |
| SenseVoice Small | `sensevoice` | ★★★☆☆ | 基线 | ~2GB | ✅ | 452MB |
| Paraformer | `paraformer` | ★★★☆☆ | ~1× | ~1.5GB | ❌ | ~1.0GB |

> **推荐**: AMD 5600 以上配置可优先尝试 `qwen_asr`（Qwen3-ASR 1.7B），准确率最高。配置较低时用默认 `sensevoice` 即可。

### 下载模型

> ⚠️ **模型文件不在本仓库中**（文件过大）。本地已有模型的目录（如 `SenseVoice-Small/`）是运行 `start_server.sh` 时自动校验使用的，不会随 git 推送。克隆仓库后需单独下载模型。

模型发布页: https://github.com/HaujetZhao/CapsWriter-Offline/releases/tag/models

下载后放入 `models/<引擎名>/` 目录，修改 `config_server.py` 的 `model_type` 后重启服务端。

**模型状态说明**（仅限本地，仓库中不包含）：

| 模型 | 本地状态 |
|------|------|
| SenseVoice Small | ✅ 已就绪 (452MB) |
| SenseVoice Small ONNX | ✅ 已就绪 |
| Qwen3-ASR 1.7B | ⚠️ 需下载 |
| Fun-ASR-Nano | ⚠️ 需下载 |
| ForceAligner | ⚠️ 需下载（Qwen3-ASR 生成精确时间戳时需要） |
| Paraformer | ✅ 已就绪 |

---

## 客户端配置要点

编辑 `config_client.py`:

```python
# 快捷键
shortcuts = [
    {'key': 'f7',  'type': 'keyboard', 'suppress': True, 'hold_mode': True,  'enabled': True},   # 按住说话
    {'key': 'f8',  'type': 'keyboard', 'suppress': True, 'hold_mode': False, 'enabled': True},   # 切换模式
]

# 文件转录
file_seg_duration = 60       # 分段长度（秒），越大内存占用越高
file_seg_overlap = 4         # 分段重叠（秒），避免切分点丢字
file_save_srt = True         # 生成 SRT 字幕
file_save_txt = True         # 生成 TXT 文本
file_save_json = True        # 生成 JSON 时间戳

# 通用
language = 'auto'            # 识别语言: 'auto' / 'chinese' / 'english'
paste = True                 # 粘贴模式（推荐开启）
enable_tray = False          # Linux 关闭托盘图标
```

> **Linux 下快捷键**: 支持 F7（按住说话）/ F8（单击切换）。鼠标侧键在 ARM64 平台可能不可用，默认禁用。
>
> **Wayland 用户**: `pynput` 依赖 X11 协议，在 Wayland 下无法正常监听全局按键，会导致快捷键无响应或误触发（如不停向服务端发送录音请求）。
>
> 解决方法：
> 1. **推荐**: 切换到 Xorg 会话登录（登录界面选 "CachyOS on Xorg" / "Ubuntu on Xorg"），快捷键即可正常工作。
> 2. **不切 Xorg**: 在 `config_client.py` 中将所有快捷键 `'enabled': False` 禁用 pynput，改用 Wayland 合成器绑键（如 Hyprland 的 `bind = , F7, exec, ...`）触发录音脚本。

---

## 项目结构

```
CapsWriter-Offline-v2.6/
├── config_client.py              # 客户端配置
├── config_server.py              # 服务端配置（引擎选择）
├── setup.sh                      # ★ 多架构一键部署脚本
├── start_server.sh / start_client.sh
├── hot.txt / hot-rule.txt        # 客户端热词（音素 RAG + 正则）
├── hot-server.txt                # 服务端热词
│
├── deps/ / deps-arm64/           # Python wheel 离线源
├── sysdeps/ / sysdeps-arm64/     # 系统 .deb 离线包
├── cpython-*-x86_64*.tar.gz      # x86_64 Python 运行时（离线引导用）
├── cpython-*-aarch64*.tar.gz     # ARM64 Python 运行时（离线引导用）
├── uv-*.tar.gz                   # uv 包管理器（离线引导用）
│
├── models/                       # ASR 模型文件
│   ├── SenseVoice-Small/         # 452MB — 默认引擎
│   ├── Fun-ASR-Nano/             # 模型下载链接 →
│   ├── Qwen3-ASR/                # 模型下载链接 →
│   └── ...
│
├── core/                         # 源码
├── LLM/                          # LLM 角色配置
└── docs/                         # 文档
```

---

## 常见问题

### 部署相关

**Q: `bash setup.sh` 报 "虚拟环境不存在" 或 Python 模块找不到？**

```bash
# 重新运行完整部署
bash setup.sh --offline --bootstrap
```

**Q: `ModuleNotFoundError: No module named 'typer'` / `'rich'` / `'srt'`？**

Python 依赖安装不完整。运行以下命令补装:

```bash
source .venv/bin/activate
pip install -r requirements.txt
```

或离线安装:

```bash
source .venv/bin/activate
pip install --no-index --find-links=deps/ -r requirements.txt
```

**Q: `runtime/python/bin/python3.11` 报 "可执行文件格式错误"？**

`runtime/` 中的 Python 是 arm64 架构，无法在 x86_64 上运行:

```bash
rm -rf runtime/
bash setup.sh --bootstrap   # 从正确的 cpython 归档重新解压
```

### 转录准确率

**Q: 转录准确率很差（尤其是歌曲/音乐）？**

可能原因及解决方案:

1. **模型太小**: 默认 SenseVoice Small 对复杂音频效果有限，考虑切换到 Qwen3-ASR（`config_server.py` 中设置 `model_type = 'qwen_asr'`）
2. **音乐/歌曲**: ASR 模型训练数据是语音，不是唱歌。推荐使用人声分离工具（如 [UVR](https://github.com/Anjok07/ultimatevocalremovergui) 或 [Demucs](https://github.com/facebookresearch/demucs)）先将人声从乐器中分离，再转录
3. **音频质量**: 128kbps MP3 压缩损失较多细节，优先使用原始 WAV/FLAC

**Q: 纯语音内容准确率也不高？**

- 确认音频为 16kHz 采样率单声道（ffmpeg 会自动转换）
- 确认 `config_server.py` 中 `model_type` 设置正确
- 查看 `logs/server_latest.log` 确认模型正常加载，无错误输出
- 尝试切换 `language` 配置: `'chinese'` / `'english'`（默认 `'auto'` 会自动检测）

### 运行时问题

**Q: 端口 6016 冲突？**

```bash
ss -tlnp | grep 6016   # 查看占用进程
kill <PID>              # 结束冲突进程
```

**Q: pynput 无法捕获按键 (Wayland)？**

```bash
echo $XDG_SESSION_TYPE   # 查看会话类型
# x11  → 正常工作
# wayland → 切换到 Xorg 登录，或在 config_client.py 中禁用快捷键监听
```

**Q: FFmpeg 未找到？**

```bash
# 在线安装
sudo apt install ffmpeg -y

# 离线安装（sysdeps/ 中已包含）
sudo dpkg -i sysdeps/ffmpeg_*.deb 2>/dev/null  # x86_64
sudo dpkg -i sysdeps-arm64/ffmpeg_*.deb 2>/dev/null  # ARM64
sudo apt install -f -y
```

---

## 离线部署到目标机

### x86_64 目标机

```bash
# 将整个项目目录复制到目标机，然后:
cd CapsWriter-Offline-v2.6
sudo dpkg -i sysdeps/*.deb 2>/dev/null; sudo apt install -f -y
bash setup.sh --offline --bootstrap
bash start_server.sh    # 终端 1
bash start_client.sh    # 终端 2
```

### ARM64 目标机

```bash
cd CapsWriter-Offline-v2.6
sudo dpkg -i sysdeps-arm64/*.deb 2>/dev/null; sudo apt install -f -y
bash setup.sh --offline --bootstrap
bash start_server.sh    # 终端 1
bash start_client.sh    # 终端 2
```

---

## 开机自启

```bash
# 启用用户级 systemd 服务
systemctl --user enable capswriter-server capswriter-client
sudo loginctl enable-linger $USER
```

---

## 更多文档

- [Ubuntu 离线部署教程](docs/Ubuntu离线部署教程.md) — 详细的部署步骤和离线包制作方法
- [windows系统文件转录功能如何使用](docs/文件转录功能如何使用.md)
- [模型下载的若干问题](docs/模型下载的若干问题.md)

---

## 许可证

MIT License — Copyright (c) 2026 Haujet Zhao

本项目基于以下来源修改:
- [HaujetZhao/CapsWriter-Offline](https://github.com/HaujetZhao/CapsWriter-Offline) (原项目, MIT)
- [new985211/CapsWriter-Offline](https://github.com/new985211/CapsWriter-Offline) v2.6-Linux release (Linux 适配 fork)

如果觉得好用，欢迎点个 Star 或者打赏支持：

**原项目作者 Haujet Zhao**（感谢原作者的辛勤开发）：

![原项目赞助码](assets/zxq.jpg)

**Linux 编译版维护者**（感谢支持持续更新）：

> （此处放置你的赞赏码图片，放入 `assets/` 目录后引用）

---
