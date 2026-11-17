#!/usr/bin/env python3
"""Prototype readiness gate for an explicitly selected private SIP broker STT."""
import argparse
import datetime
import hashlib
import importlib
import json
import os
from pathlib import Path
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bridge-dir', type=Path, required=True)
    parser.add_argument('--provider', choices=('whisper', 'speechkit'), required=True)
    parser.add_argument('--check-only', action='store_true')
    args = parser.parse_args()
    os.environ['VOICE_STT_PROVIDER'] = args.provider
    sys.path.insert(0, str(args.bridge_dir.resolve()))
    bridge = importlib.import_module('dialog_bridge')
    if args.provider == 'whisper':
        if bridge.whisper_request('/health', timeout=10).get('device') != 'cuda':
            raise RuntimeError('Whisper must be ready on CUDA')
        pcm = (args.bridge_dir / 'whisper-readiness.sln').read_bytes()
    else:
        # Own generated test phrase, never an old private meeting recording.
        pcm = bridge.synthesize('Проверка связи. Облачное распознавание готово к разговору.')
    started = time.monotonic()
    text = bridge.transcribe(pcm)
    if not text:
        raise RuntimeError('Selected recognizer returned no text for speech')
    proof = {
        'checked_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'provider': args.provider, 'input_seconds': len(pcm) / 16000,
        'input_sha256': hashlib.sha256(pcm).hexdigest(), 'text': text,
        'stt_seconds': round(time.monotonic() - started, 3),
        'automatic_stt_switch': False,
    }
    (args.bridge_dir / (args.provider + '-readiness-proof.json')).write_text(
        json.dumps(proof, ensure_ascii=False, indent=2) + '\n')
    print('stt_ready ' + json.dumps({k: v for k, v in proof.items()
                                    if k not in ('text', 'input_sha256')}), flush=True)
    if not args.check_only:
        # Keep broker argv private and independent from readiness CLI options.
        sys.argv = [str(args.bridge_dir / 'dialog_bridge.py')]
        bridge.main()


if __name__ == '__main__':
    main()
