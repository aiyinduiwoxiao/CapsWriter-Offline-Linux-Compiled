# coding: utf-8
"""Linux 客户端配置"""
import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))


class LinuxConfig:
    # 服务端连接
    addr = '127.0.0.1'
    port = '6016'

    # 快捷键
    hotkey = 'caps_lock'
    threshold = 0.3

    # 输出
    paste = True                # True=粘贴模式(推荐), False=打字模式
    restore_clip = True

    # 识别
    context = ''
    language = 'auto'
    trash_punc = '，。,.'

    # 音频
    mic_seg_duration = 15       # 分段时长（秒）
    mic_seg_overlap = 2
    mic_device = None
