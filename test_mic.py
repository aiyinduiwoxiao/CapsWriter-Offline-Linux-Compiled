#!/usr/bin/env python3
"""Quick end-to-end test: record mic → send to ASR server → print result."""
import sys
from pathlib import Path
# 确保项目根目录在 sys.path 中
_project_root = Path(__file__).resolve().parent
if str(_project_root) not in sys.path:
    sys.path.insert(0, str(_project_root))

import asyncio
import base64
import json
import time
import uuid
import numpy as np
import sounddevice as sd
import websockets
from core.protocol import AudioMessage, RecognitionMessage


SAMPLE_RATE = 16000
DURATION = 5  # Record for 5 seconds
SERVER = 'ws://127.0.0.1:6016'


def record_mic(duration: float, device=None) -> bytes:
    print(f"Recording {duration}s from microphone...")
    audio = sd.rec(
        int(duration * SAMPLE_RATE),
        samplerate=SAMPLE_RATE,
        channels=1,
        dtype='float32',
        device=device,
    )
    sd.wait()
    print(f"Recorded {len(audio)} samples ({len(audio)/SAMPLE_RATE:.1f}s)")
    return audio.tobytes()


async def send_to_server(audio_raw: bytes) -> str:
    audio_b64 = base64.b64encode(audio_raw).decode('ascii')
    task_id = uuid.uuid4().hex

    msg = AudioMessage(
        task_id=task_id, source='mic', data=audio_b64,
        is_final=True, time_start=time.time(),
        seg_duration=DURATION + 1, seg_overlap=0,
        context='', language='auto',
    )

    async with websockets.connect(SERVER, max_size=10*1024*1024, subprotocols=['binary']) as ws:
        await ws.send(msg.to_json())
        response = await ws.recv()
        result = RecognitionMessage.from_dict(json.loads(response))
        return result.text


async def main():
    print("CapsWriter Linux — Mic Test")
    print(f"Server: {SERVER}")
    print(f"Speaking duration: {DURATION}s")
    print()

    # Check devices
    print("Audio devices:")
    print(sd.query_devices())
    print()

    # Record
    audio_raw = record_mic(DURATION)

    # Send to server
    print("Sending to ASR server...")
    t0 = time.time()
    text = await send_to_server(audio_raw)
    elapsed = time.time() - t0

    print(f"\nRecognition result ({elapsed:.2f}s):")
    print(f"  >>> {text} <<<")


if __name__ == '__main__':
    asyncio.run(main())
