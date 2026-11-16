#!/usr/bin/python3
"""Publish one TTS result to a specified existing SIP call, never to a later call."""
import argparse
import json
import os
import re
import time
import uuid
from pathlib import Path

RUNTIME = Path('/run/voice-sip-probe')


def publish_audio(runtime, call_id, pcm, expected_epoch=None):
    if not re.fullmatch(r'call-[A-Za-z0-9_-]{1,64}', call_id):
        raise ValueError('Invalid call ID')
    if not 100 < len(pcm) <= 960000 or len(pcm) % 2:
        raise ValueError('Invalid push audio')
    active = json.loads((runtime/'active-call.json').read_text())
    if active.get('call_id') != call_id:
        raise ValueError('Call ended or changed; result will not be redirected')
    if 'epoch' in active:
        if active.get('mode') not in ('listening','thinking','speaking'):
            raise ValueError('Voice is paused')
        if expected_epoch != active['epoch']:
            raise ValueError('Voice generation changed; old result suppressed')
    queue = runtime / call_id / 'push'
    if queue.resolve() != queue or not queue.is_dir():
        raise ValueError('Missing or unsafe call queue')
    name = (f'g{expected_epoch}-' if 'epoch' in active else '') + uuid.uuid4().hex
    temporary = queue / (name + '.pending')
    final = queue / (name + '.sln')
    temporary.write_bytes(pcm)
    # Queue directory is private to Asterisk; root producer grants it read access.
    temporary.chmod(0o644)
    temporary.rename(final)
    return final


def deliver_after_reply(runtime, call_id, sequence, delay_s, pcm, now=time.monotonic, wait=time.sleep, expected_epoch=None):
    deadline = now() + 240
    ready_at = None
    while now() < deadline:
        active = json.loads((runtime/'active-call.json').read_text())
        if active.get('call_id') != call_id:
            raise ValueError('Call ended or changed while waiting')
        if 'epoch' in active and (active['epoch'] != expected_epoch or active.get('mode')=='paused'):
            raise ValueError('Voice paused or changed while waiting')
        try:
            finished = json.loads((runtime/call_id/'reply-finished.json').read_text())
        except FileNotFoundError:
            finished = {}
        if ready_at is None and finished.get('sequence', 0) >= sequence:
            ready_at = finished['at'] + delay_s
        if ready_at is not None and now() >= ready_at:
            return publish_audio(runtime, call_id, pcm, expected_epoch)
        wait(0.25)
    raise TimeoutError('No completed normal reply within demo window')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--call-id', required=True)
    parser.add_argument('--audio-file', type=Path, required=True)
    parser.add_argument('--after-sequence', type=int)
    parser.add_argument('--delay-s', type=int, default=20)
    parser.add_argument('--epoch', type=int)
    args = parser.parse_args()
    pcm = args.audio_file.read_bytes()
    if args.after_sequence is None:
        queued = publish_audio(RUNTIME, args.call_id, pcm, args.epoch)
    else:
        queued = deliver_after_reply(RUNTIME, args.call_id, args.after_sequence, args.delay_s, pcm, expected_epoch=args.epoch)
    print(json.dumps({'event':'sip_push_queued','call_id':args.call_id,'push_id':queued.stem}), flush=True)


if __name__ == '__main__':
    main()
