#!/usr/bin/env python3
"""Opt-in live SIP test: steady paused media, client crash, slot/model cleanup.

Requires an isolated running probe and a private, already configured Baresip
directory. It never calls a person, opens ingress, or starts home STT.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time


def model_workers():
    found = []
    for folder in Path('/proc').glob('[0-9]*'):
        try:
            args = (folder / 'cmdline').read_bytes().split(b'\0')
            if len(args) > 1 and args[1].endswith(b'/sip_control/worker.py'):
                found.append(int(folder.name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assets', type=Path, required=True)
    parser.add_argument('--client-dir', type=Path, required=True)
    parser.add_argument('--sip-target', required=True)
    parser.add_argument('--steady-seconds', type=float, default=0)
    parser.add_argument('--timeout', type=float, default=70)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    if args.steady_seconds < 0 or not 0 < args.timeout <= 180:
        parser.error('invalid observation bounds')
    if not args.sip_target.startswith('sip:7304@'):
        parser.error('only the isolated 7304 probe extension is supported')
    env = dict(os.environ, LD_LIBRARY_PATH=(
        str(args.assets / 'asterisk-runtime') + ':' +
        str(args.assets / 'rootfs/usr/lib/x86_64-linux-gnu')))

    def cli(command):
        return subprocess.check_output([
            str(args.assets / 'active-asterisk'), '-C',
            '/run/voice-sip-probe/etc/asterisk.conf', '-rx', command,
        ], env=env, text=True, timeout=5)

    if '0 active channels' not in cli('core show channels count') or model_workers():
        raise RuntimeError('Probe already has a call/worker; test refused')
    proof = {'phase': 'starting', 'model_workers_before': [], 'pass': False}
    proc = None
    channel = None
    manifest = Path('/run/voice-sip-probe/active-call.json')

    def save():
        args.out.write_text(json.dumps(proof, ensure_ascii=False, indent=2) + '\n')

    def paused():
        try:
            return json.loads(manifest.read_text()).get('mode') == 'paused'
        except (FileNotFoundError, json.JSONDecodeError):
            return False

    save()
    try:
        with args.out.with_suffix('.log').open('w') as log:
            proc = subprocess.Popen([
                str(args.assets / 'rootfs/usr/bin/baresip'),
                '-f', str(args.client_dir),
                '-t', str(int(args.timeout + args.steady_seconds + 40)),
                '-e', '/dial ' + args.sip_target,
            ], env=env, stdin=subprocess.PIPE, stdout=log, stderr=log)
            deadline = time.monotonic() + 25
            while not (paused() and model_workers()):
                if proc.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError('Paused test call did not become ready')
                time.sleep(.1)
            channels = [line.split('!', 1)[0]
                        for line in cli('core show channels concise').splitlines()
                        if line.startswith('PJSIP/') and '!7304!' in line]
            if len(channels) != 1:
                raise RuntimeError('Cannot identify the isolated test channel')
            channel = channels[0]
            proof.update(phase='steady', worker_count_during_call=len(model_workers()))
            save()
            deadline = time.monotonic() + args.steady_seconds
            while time.monotonic() < deadline:
                if proc.poll() is not None or not paused():
                    raise RuntimeError('Steady paused call was interrupted')
                time.sleep(.2)
            proof.update(phase='client_lost', steady_seconds=args.steady_seconds)
            save()
            started = time.monotonic()
            proc.kill()  # Only the exact test client created above; no SIP BYE.
            proc.wait(timeout=5)
            deadline = started + args.timeout
            while manifest.exists() or model_workers() or '0 active channels' not in cli('core show channels count'):
                if time.monotonic() >= deadline:
                    raise RuntimeError('Abandoned call/model exceeded cleanup deadline')
                time.sleep(.2)
            proof.update(phase='finished', cleanup_seconds=round(time.monotonic()-started, 3),
                         worker_count_after=0, active_channels_after=0, **{'pass': True})
    finally:
        if proc is not None and proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=5)
        if channel and channel in cli('core show channels concise'):
            proof['forced_test_cleanup'] = True
            cli('channel request hangup ' + channel)
        save()
    print(json.dumps(proof, ensure_ascii=False))


if __name__ == '__main__':
    main()
