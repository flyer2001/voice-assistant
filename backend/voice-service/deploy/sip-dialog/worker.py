#!/usr/bin/python3
"""One model and full-duplex AudioSocket for one already answered call."""
import argparse
import ctypes
from collections import defaultdict
import json
import os
from pathlib import Path
import queue
import resource
import select
import signal
import socket
import struct
import sys
import threading
import time
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parent))
from control import VoiceControl, FRAME_BYTES
from detector import CommandDetector


def atomic_json(path, value):
    temporary = path.with_suffix('.pending')
    temporary.write_text(json.dumps(value) + '\n')
    temporary.replace(path)


def bind_to_parent(parent_pid):
    # Linux PR_SET_PDEATHSIG: a killed AGI must not leave a model or listener behind.
    if ctypes.CDLL(None, use_errno=True).prctl(1, signal.SIGTERM, 0, 0, 0) != 0:
        raise OSError(ctypes.get_errno(), 'Cannot bind model lifecycle to call')
    if os.getppid() != parent_pid:
        raise RuntimeError('Call owner already exited')


class Frames:
    def __init__(self):
        self.buffer = bytearray()

    def feed(self, data):
        self.buffer.extend(data)
        frames = []
        while len(self.buffer) >= 3:
            kind, size = struct.unpack('!BH', self.buffer[:3])
            if len(self.buffer) < size + 3:
                break
            payload = bytes(self.buffer[3:size+3])
            del self.buffer[:size+3]
            if kind == 0x10 and size % 2:
                raise ValueError('Odd PCM frame')
            if kind == 0x10 and size > 16000:
                raise ValueError('Oversized PCM frame')
            frames.append((kind, payload))
        return frames


def rpc(bridge, pcm):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(135)
        client.connect(str(bridge))
        client.sendall(b'A' + pcm)
        client.shutdown(socket.SHUT_WR)
        with client.makefile('rb') as stream:
            return stream.read(960002)


def serve(client, detector, control, root, nonce, bridge):
    parser = Frames()
    completed = queue.Queue()
    starting = time.monotonic()
    next_output = starting
    next_queue = starting
    authenticated = False
    sequence = 0
    counts = defaultdict(int)
    modes = defaultdict(float)
    events = []
    last_at = starting
    manifest = root.parent / 'active-call.json'

    def publish():
        atomic_json(manifest, {'call_id':root.name, 'mode':control.mode,
                               'epoch':control.epoch, 'worker_pid':os.getpid()})

    def submit(job):
        epoch, pcm = job

        def work():
            try:
                result = rpc(bridge, pcm)
            except (OSError, ValueError):
                result = b'E'
            completed.put((epoch, result))

        # An old backend turn may finish later; it cannot keep the model alive on hangup.
        threading.Thread(target=work, daemon=True).start()
        counts['ordinary_stt_requests'] += 1

    client.settimeout(1)
    publish()
    while time.monotonic() - starting < 50 * 60:
        now = time.monotonic()
        modes[control.mode] += now - last_at
        last_at = now
        if not authenticated and now - starting > 10:
            raise TimeoutError('No call UUID')
        delay = max(0, min(.02, next_output-now)) if authenticated else .02
        readers, _, _ = select.select([client], [], [], delay)
        if readers:
            data = client.recv(8192)
            if not data:
                break
            for kind, payload in parser.feed(data):
                if kind == 0:
                    return dict(counts), dict(modes), events
                if not authenticated:
                    if kind != 1 or payload != nonce.bytes:
                        raise ValueError('Wrong call UUID')
                    authenticated = True
                    control.connected()
                    continue
                if kind == 3 and payload == b'#':
                    job = control.submit()
                    if job:
                        submit(job)
                    continue
                if kind != 0x10:
                    continue
                before = control.epoch
                phrase = detector.feed(payload)
                if phrase:
                    control.command(phrase)
                    if before != control.epoch:
                        counts['starts' if control.mode == 'ready' else 'stops'] += 1
                        events.append({'action':'start' if control.mode=='ready' else 'stop',
                                       'at_s':round(time.monotonic()-starting,3)})
                        detector.reset()
                        publish()
                job = control.receive(payload)
                if job:
                    submit(job)
                    publish()
        while not completed.empty():
            epoch, response = completed.get_nowait()
            if not control.result(epoch, response):
                counts['stale_results_discarded'] += 1
            publish()
        now = time.monotonic()
        if now >= next_queue:
            for pending in sorted((root/'push').glob('*.sln')):
                valid_epoch = pending.stem.startswith(f'g{control.epoch}-')
                if control.mode == 'paused' or not valid_epoch:
                    pending.rename(pending.with_suffix('.suppressed'))
                    counts['push_suppressed'] += 1
                elif control.push(control.epoch, pending.read_bytes()):
                    pending.unlink()
                    counts['push_played'] += 1
                    publish()
                    break
            next_queue = now + .25
        if authenticated and now >= next_output:
            if control.heartbeat(now-starting):
                counts['heartbeats'] += 1
            frame = control.output_frame()
            client.sendall(struct.pack('!BH', 0x10, len(frame)) + frame)
            if control.last_finished:
                if control.last_finished == 'reply':
                    sequence += 1
                    atomic_json(root/'reply-finished.json', {'sequence':sequence, 'at':now})
                publish()
            next_output = max(next_output + .02, now)
    return dict(counts), dict(modes), events


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--parent-pid', type=int, required=True)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--uuid', type=uuid.UUID, required=True)
    parser.add_argument('--bridge', type=Path, default=Path('/run/voice-sip-dialog.sock'))
    parser.add_argument('--heartbeat', type=float, default=45)
    parser.add_argument('--start-phrase', default='голосовой помощник слушай')
    parser.add_argument('--stop-phrase', default='голосовой помощник пауза')
    parser.add_argument('--reject-phrases', default='[]')
    args = parser.parse_args()
    rejects = json.loads(args.reject_phrases)
    if not isinstance(rejects, list) or len(rejects) > 32 or not all(isinstance(p, str) and 1 <= len(p) <= 120 for p in rejects):
        parser.error('Invalid contrast phrases')
    bind_to_parent(args.parent_pid)
    start_wall, start_cpu = time.monotonic(), time.process_time()
    print(json.dumps({'event':'control_loading','pid':os.getpid()}),file=sys.stderr,flush=True)
    control = VoiceControl(heartbeat_seconds=args.heartbeat,
                           start_phrase=args.start_phrase,stop_phrase=args.stop_phrase)
    detector = CommandDetector(args.model, [control.start_phrase, control.stop_phrase], rejects)
    loaded_wall, loaded_cpu = time.monotonic(), time.process_time()
    print(json.dumps({'event':'control_loaded','cpu_s':loaded_cpu-start_cpu}),file=sys.stderr,flush=True)
    counts, modes, events, error = {}, {}, [], ''
    try:
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            listener.listen(1)
            listener.settimeout(30)
            atomic_json(args.root/'control-ready.json',
                        {'port':listener.getsockname()[1], 'pid':os.getpid()})
            client, _ = listener.accept()
            with client:
                counts, modes, events = serve(client, detector, control, args.root, args.uuid, args.bridge)
    except (OSError, ValueError) as exc:
        error = type(exc).__name__
    finally:
        usage = resource.getrusage(resource.RUSAGE_SELF)
        report = {'event':'voice_control_finished', 'pid':os.getpid(),
                  'load_wall_s':round(loaded_wall-start_wall,3),
                  'load_cpu_s':round(loaded_cpu-start_cpu,3),
                  'run_wall_s':round(time.monotonic()-loaded_wall,3),
                  'run_cpu_s':round(time.process_time()-loaded_cpu,3),
                  'rss_peak_mib':round(usage.ru_maxrss/1024,1),
                  'counts':counts, 'modes_s':modes, 'command_events':events, 'error':error}
        atomic_json(args.root/'control-metrics.json', report)
        print(json.dumps(report), file=sys.stderr, flush=True)


if __name__ == '__main__':
    main()
