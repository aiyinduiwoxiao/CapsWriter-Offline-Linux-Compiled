# coding: utf-8
"""
CapsWriter Linux 服务端 — 精简入口
跳过托盘/Toast 等 Windows GUI 组件，仅启动 ASR + WebSocket。
"""
import os
import sys
import asyncio
import logging
from pathlib import Path

# Python path setup
_PROJECT_DIR = Path(__file__).parents[2]
os.chdir(_PROJECT_DIR)
if str(_PROJECT_DIR) not in sys.path:
    sys.path.insert(0, str(_PROJECT_DIR))

from config_server import ServerConfig as Config, __version__
from core.tools.signal_handler import register_signal
from core.server.worker.process_manager import ProcessManager
from core.server.connection.server_manager import SocketManager
from core.server.state import ServerState, console

logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s [%(name)s] %(message)s',
    datefmt='%H:%M:%S',
)
logger = logging.getLogger('linux_server')


class CapsWriterLinuxServer:

    def __init__(self):
        self.base_dir = _PROJECT_DIR
        os.chdir(self.base_dir)
        self.loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)
        self.state = ServerState(app=self)
        self.process_manager = ProcessManager(self)
        self.socket_manager = SocketManager(self)
        self.is_alive = False

    def _print_banner(self):
        console.line(2)
        console.rule('[bold #d55252]CapsWriter Offline Server (Linux)[/]')
        console.line()
        console.print(f'版本：[bold green]{__version__}[/]', end='\n\n')
        console.print(f'模型类型：[bold cyan]{Config.model_type}[/]')
        console.print(f'服务地址：[cyan underline]{Config.addr}:{Config.port}[/]', end='\n\n')

    def stop(self):
        if not self.is_alive:
            return
        self.is_alive = False
        logger.info("清理服务端资源...")
        self.state.queue_out.put(None)
        self.socket_manager.stop()
        self.process_manager.stop()
        self.loop.stop()
        logger.info("服务端已停止")
        console.print('[green4]再见！[/]')

    def start(self):
        if self.is_alive:
            return
        self.is_alive = True
        register_signal(self.stop)
        self._print_banner()
        self.process_manager.start()
        try:
            self.loop.run_until_complete(self.socket_manager.start())
        except RuntimeError:
            pass


if __name__ == '__main__':
    app = CapsWriterLinuxServer()
    app.start()
