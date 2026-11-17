#!/usr/bin/python3
"""Asterisk AGI entry: creates a model worker only after CHANNEL STATUS is Up."""
import json
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import sys
import tempfile
import time
import uuid

RUNTIME = Path('/run/voice-sip-probe')
ASSETS = Path(__file__).resolve().parent.parent


def agi(command):
    print(command, flush=True)
    match = re.match(r'200 result=(-?\d+)', sys.stdin.readline())
    if not match or match[1] == '-1':
        raise EOFError
    return int(match[1])


def mark(command):
    try:
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(2)
            client.connect('/run/voice-sip-dialog.sock')
            client.sendall(command)
            client.shutdown(socket.SHUT_WR)
            client.recv(1)
    except OSError:
        pass


def hangup(*_):
    raise EOFError


def main():
    environment = {}
    while line := sys.stdin.readline():
        if not line.strip():
            break
        key, _, value = line.partition(':')
        environment[key] = value.strip()
    if not environment.get('agi_channel') or not environment.get('agi_uniqueid'):
        return 2
    if agi('CHANNEL STATUS') != 6:
        return 3
    signal.signal(signal.SIGHUP, hangup)
    signal.signal(signal.SIGTERM, hangup)
    mark(b'S')
    with tempfile.TemporaryDirectory(prefix='call-', dir=RUNTIME) as folder:
        root = Path(folder)
        (root/'push').mkdir(mode=0o700)
        manifest = RUNTIME/'active-call.json'
        manifest.write_text(json.dumps({'call_id':root.name, 'mode':'initializing', 'epoch':0}))
        child = None
        try:
            nonce = str(uuid.uuid4())
            settings_path=ASSETS/'sip_control/settings.json'
            settings=json.loads(settings_path.read_text()) if settings_path.exists() else {}
            start_phrase=settings.get('start_phrase','голосовой помощник слушай')
            stop_phrase=settings.get('stop_phrase','голосовой помощник пауза')
            heartbeat=float(settings.get('heartbeat_seconds',45))
            rejects=settings.get('reject_phrases',[])
            if not 0 <= heartbeat <= 300 or not all(isinstance(p,str) and 3 <= len(p) <= 120 for p in (start_phrase,stop_phrase)):
                raise ValueError('Invalid voice-control settings')
            if not isinstance(rejects,list) or len(rejects)>32 or not all(isinstance(p,str) and 1<=len(p)<=120 for p in rejects):
                raise ValueError('Invalid contrast phrases')
            env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', OPENBLAS_NUM_THREADS='1', OMP_NUM_THREADS='1')
            with (root/'control.log').open('w') as log:
                child = subprocess.Popen([
                    str(ASSETS/'control-venv/bin/python3'), str(ASSETS/'sip_control/worker.py'),
                    '--root', str(root), '--uuid', nonce,
                    '--parent-pid',str(os.getpid()),
                    '--model', str(ASSETS/'vosk-model-small-ru-0.22'),
                    '--start-phrase',start_phrase,'--stop-phrase',stop_phrase,
                    '--reject-phrases',json.dumps(rejects,ensure_ascii=False),
                    '--heartbeat',str(heartbeat),
                ], env=env, stdout=subprocess.DEVNULL, stderr=log)
                deadline = time.monotonic() + 30
                ready = root/'control-ready.json'
                while not ready.exists():
                    if child.poll() is not None:
                        raise RuntimeError('Call detector failed to start')
                    if time.monotonic() >= deadline:
                        raise TimeoutError('Call detector startup timeout')
                    time.sleep(.05)
                info = json.loads(ready.read_text())
                agi(f'VERBOSE "voice_control started pid={child.pid}" 1')
                agi(f'EXEC AudioSocket "{nonce},127.0.0.1:{info["port"]}"')
                # AudioSocket sends hangup/EOF; let the worker write its result first.
                try:
                    child.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    child.terminate()
        finally:
            if child is not None:
                if child.poll() is None:
                    try:
                        child.wait(timeout=1.5)
                    except subprocess.TimeoutExpired:
                        child.terminate()
                        try:
                            child.wait(timeout=3)
                        except subprocess.TimeoutExpired:
                            child.kill()
                            child.wait()
                metrics = root/'control-metrics.json'
                if metrics.exists():
                    # Numeric state/resource data only, no caller speech in logs.
                    try:
                        agi('VERBOSE "control_metrics ' + metrics.read_text().strip().replace('"', '\\"') + '" 1')
                    except EOFError:
                        pass
            try:
                if json.loads(manifest.read_text()).get('call_id') == root.name:
                    manifest.unlink()
            except FileNotFoundError:
                pass
            mark(b'F')
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except EOFError:
        pass
