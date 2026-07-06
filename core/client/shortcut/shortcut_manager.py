# coding: utf-8
"""
快捷键管理器

统一管理多个快捷键，处理键盘和鼠标事件，支持：
1. 多快捷键并发处理
2. hold_mode 和 click_mode 支持
3. Windows (win32_event_filter) 和 Linux (on_press/on_release) 双平台
"""
from __future__ import annotations
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from typing import TYPE_CHECKING, Dict, List, Optional

from pynput import keyboard, mouse

from . import logger
from core.client.shortcut.key_mapper import *
from core.client.shortcut.key_mapper import KeyMapper, IS_WINDOWS, IS_LINUX
from core.client.shortcut.emulator import ShortcutEmulator
from core.client.shortcut.event_handler import ShortcutEventHandler
from core.client.shortcut.task import ShortcutTask

if TYPE_CHECKING:
    from core.client.shortcut.shortcut_config import Shortcut
    from core.client.state import ClientState
    from core.client.app import CapsWriterClient


def _pynput_key_to_name(key) -> Optional[str]:
    """将 pynput Key/KeyCode 转换为字符串名称 (Linux 用)"""
    if isinstance(key, keyboard.Key):
        name = key.name
        # 规范化常见名称
        if name == 'caps_lock':
            return 'caps_lock'
        if name == 'num_lock':
            return 'num_lock'
        if name == 'scroll_lock':
            return 'scroll_lock'
        if name == 'ctrl_l':
            return 'ctrl_l'
        if name == 'ctrl_r':
            return 'ctrl_r'
        if name == 'shift_l':
            return 'shift'
        if name == 'shift_r':
            return 'shift_r'
        if name == 'alt_l':
            return 'alt_l'
        if name == 'alt_gr':
            return 'alt_gr'
        return name
    elif isinstance(key, keyboard.KeyCode):
        # 普通字符键
        if key.char:
            return key.char
        return f'vk_{key.vk}'
    return None


def _pynput_mouse_to_name(button) -> Optional[str]:
    """将 pynput mouse Button 转换为字符串名称。仅处理侧键，其余返回 None。"""
    name = getattr(button, 'name', '')
    if name in ('x1', 'x2'):
        return name
    return None


class ShortcutManager:
    """快捷键管理器 — Windows + Linux 双平台"""

    def __init__(self, app: CapsWriterClient, shortcuts: List[Shortcut]):
        self.app = app
        self.shortcuts = shortcuts

        self.keyboard_listener: Optional[keyboard.Listener] = None
        self.mouse_listener: Optional[mouse.Listener] = None

        self.tasks: Dict[str, ShortcutTask] = {}
        self._pool = ThreadPoolExecutor(max_workers=4)
        self._emulator = ShortcutEmulator()
        self._restoring_keys = set()

        self._init_tasks()
        self._event_handler = ShortcutEventHandler(self.tasks, self._pool, self._emulator)

    @property
    def state(self) -> ClientState:
        return self.app.state

    def _init_tasks(self) -> None:
        from config_client import ClientConfig as Config
        for shortcut in self.shortcuts:
            if not shortcut.enabled:
                continue
            task = ShortcutTask(self.app, shortcut)
            task._manager_ref = lambda: self
            task.pool = self._pool
            task.threshold = shortcut.get_threshold(Config.threshold)
            self.tasks[shortcut.key] = task

    # ========== Linux: on_press / on_release ==========

    def _on_press_linux(self, key):
        key_name = _pynput_key_to_name(key)
        if key_name is None:
            return
        if key_name not in self.tasks:
            return
        task = self.tasks[key_name]
        self._event_handler.handle_keydown(key_name, task)

    def _on_release_linux(self, key):
        key_name = _pynput_key_to_name(key)
        if key_name is None:
            return
        if key_name not in self.tasks:
            return
        task = self.tasks[key_name]
        self._event_handler.handle_keyup(key_name, task)

    def _on_mouse_click_linux(self, x, y, button, pressed):
        if pressed:
            # mouse press
            key_name = _pynput_mouse_to_name(button)
            if key_name and key_name in self.tasks:
                self._event_handler.handle_keydown(key_name, self.tasks[key_name])
        else:
            # mouse release
            key_name = _pynput_mouse_to_name(button)
            if key_name and key_name in self.tasks:
                task = self.tasks[key_name]
                self._handle_mouse_keyup(key_name, task)

    # ========== Windows: win32_event_filter ==========

    def create_keyboard_filter(self):
        def win32_event_filter(msg, data):
            if msg not in KEYBOARD_MESSAGES:
                return True
            key_name = KeyMapper.vk_to_name(data.vkCode)
            if self._check_emulating(key_name, msg):
                return True
            if self._check_restoring(key_name, msg):
                return True
            if key_name not in self.tasks:
                return True
            task = self.tasks[key_name]
            if msg in KEY_DOWN_MESSAGES:
                self._event_handler.handle_keydown(key_name, task)
            elif msg in KEY_UP_MESSAGES:
                self._event_handler.handle_keyup(key_name, task)
            if task.shortcut.suppress and self.keyboard_listener:
                self.keyboard_listener.suppress_event()
            return True
        return win32_event_filter

    def create_mouse_filter(self):
        def win32_event_filter(msg, data):
            if msg not in MOUSE_MESSAGES:
                return True
            xbutton = (data.mouseData >> 16) & 0xFFFF
            button_name = 'x1' if xbutton == XBUTTON1 else 'x2'
            if self._check_emulating(button_name, msg, is_mouse=True):
                return True
            if button_name not in self.tasks:
                return True
            task = self.tasks[button_name]
            if msg == WM_XBUTTONDOWN:
                self._event_handler.handle_keydown(button_name, task)
            elif msg == WM_XBUTTONUP:
                self._handle_mouse_keyup(button_name, task)
            if task.shortcut.suppress and self.mouse_listener:
                self.mouse_listener.suppress_event()
            return True
        return win32_event_filter

    def _handle_mouse_keyup(self, button_name: str, task) -> None:
        if not task.shortcut.hold_mode:
            if task.pressed:
                task.pressed = False
                task.released = True
                task.event.set()
            return
        if not task.is_recording:
            return
        duration = time.time() - task.recording_start_time
        logger.debug(f"[{button_name}] 松开按键，持续时间: {duration:.3f}s")
        if duration < task.threshold:
            task.cancel()
            if task.shortcut.suppress:
                logger.debug(f"[{button_name}] 安排异步补发鼠标按键")
                self._pool.submit(self._emulator.emulate_mouse_click, button_name)
        else:
            task.finish()

    # ========== 按键恢复 ==========

    def schedule_restore(self, key: str) -> None:
        from pynput import keyboard
        self._restoring_keys.add(key)
        def do_restore():
            import time
            time.sleep(0.05)
            if key == 'caps_lock':
                controller = keyboard.Controller()
                controller.press(keyboard.Key.caps_lock)
                controller.release(keyboard.Key.caps_lock)
        self._pool.submit(do_restore)

    def is_restoring(self, key: str) -> bool:
        return key in self._restoring_keys

    def clear_restoring_flag(self, key: str) -> None:
        self._restoring_keys.discard(key)

    # ========== 防自捕获 ==========

    def _check_emulating(self, key_name: str, msg: int, is_mouse: bool = False) -> bool:
        if not self._emulator.is_emulating(key_name):
            return False
        if is_mouse:
            if msg == WM_XBUTTONUP:
                self._emulator.clear_emulating_flag(key_name)
        else:
            if msg in (WM_KEYUP, WM_SYSKEYUP):
                self._emulator.clear_emulating_flag(key_name)
        return True

    def _check_restoring(self, key_name: str, msg: int) -> bool:
        if not self.is_restoring(key_name):
            return False
        if msg in (WM_KEYUP, WM_SYSKEYUP):
            self.clear_restoring_flag(key_name)
        return True

    # ========== 公共接口 ==========

    def start(self) -> None:
        has_keyboard = any(s.type == 'keyboard' for s in self.shortcuts if s.enabled)
        has_mouse = any(s.type == 'mouse' for s in self.shortcuts if s.enabled)

        if has_keyboard:
            if self.keyboard_listener and self.keyboard_listener.is_alive():
                logger.debug("键盘监听器已在运行，跳过启动")
            else:
                if IS_WINDOWS:
                    self.keyboard_listener = keyboard.Listener(
                        win32_event_filter=self.create_keyboard_filter()
                    )
                else:
                    # Linux: 使用标准 on_press/on_release
                    self.keyboard_listener = keyboard.Listener(
                        on_press=self._on_press_linux,
                        on_release=self._on_release_linux,
                    )
                self.keyboard_listener.start()
                logger.info(f"键盘监听器已启动 ({sys.platform})")

        if has_mouse:
            if self.mouse_listener and self.mouse_listener.is_alive():
                logger.debug("鼠标监听器已在运行，跳过启动")
            else:
                if IS_WINDOWS:
                    self.mouse_listener = mouse.Listener(
                        win32_event_filter=self.create_mouse_filter()
                    )
                else:
                    self.mouse_listener = mouse.Listener(
                        on_click=self._on_mouse_click_linux
                    )
                self.mouse_listener.start()
                logger.info(f"鼠标监听器已启动 ({sys.platform})")

        for shortcut in self.shortcuts:
            if shortcut.enabled:
                mode = "长按" if shortcut.hold_mode else "单击"
                logger.info(f"  [{shortcut.key}] {mode}模式")

    def stop(self) -> None:
        if self.keyboard_listener:
            try:
                self.keyboard_listener.stop()
            except Exception:
                pass
            finally:
                self.keyboard_listener = None
        if self.mouse_listener:
            try:
                self.mouse_listener.stop()
            except Exception:
                pass
            finally:
                self.mouse_listener = None
        for task in self.tasks.values():
            if task.is_recording:
                task.cancel()
        self._pool.shutdown(wait=False)
        logger.debug("快捷键管理器已停止")
