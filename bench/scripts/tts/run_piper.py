#!/usr/bin/env python3
"""Piper TTS local (ONNX) — ru_RU-irina-medium voice by default.

Downloads model from HuggingFace rhasspy/piper-voices on first run into
~/.cache/piper/. ONNX runtime on CPU is fast (~0.1× realtime on M1).
"""
from __future__ import annotations

import io
import os
import sys
import time
import urllib.request
import wave
from pathlib import Path

from lib import (
    Sample,
    append_metric,
    audio_duration_s,
    load_corpus,
    sample_path,
)

PROVIDER = "piper"
DEFAULT_VOICE = "ru_RU-irina-medium"
CACHE_DIR = Path.home() / ".cache" / "piper"
HF_BASE = "https://huggingface.co/rhasspy/piper-voices/resolve/main"

VOICE_PATHS = {
    "ru_RU-irina-medium": "ru/ru_RU/irina/medium",
    "ru_RU-dmitri-medium": "ru/ru_RU/dmitri/medium",
}

USD_PER_CHAR = 0.0  # local, free


def ensure_model(voice: str) -> tuple[Path, Path]:
    sub = VOICE_PATHS.get(voice)
    if not sub:
        raise RuntimeError(f"unknown voice '{voice}' (known: {list(VOICE_PATHS)})")
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    onnx_path = CACHE_DIR / f"{voice}.onnx"
    json_path = CACHE_DIR / f"{voice}.onnx.json"
    for path, suffix in [(onnx_path, ".onnx"), (json_path, ".onnx.json")]:
        if path.exists():
            continue
        url = f"{HF_BASE}/{sub}/{voice}{suffix}?download=true"
        print(f"  downloading {url} → {path}")
        urllib.request.urlretrieve(url, path)
    return onnx_path, json_path


def main() -> int:
    voice = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_VOICE
    from piper import PiperVoice  # type: ignore

    onnx_path, json_path = ensure_model(voice)
    pv = PiperVoice.load(str(onnx_path), config_path=str(json_path))

    for phrase in load_corpus():
        out = sample_path(PROVIDER, voice, phrase.id, "wav")
        start = time.perf_counter()
        with wave.open(str(out), "wb") as wf:
            pv.synthesize_wav(phrase.text, wf)
        latency_ms = int((time.perf_counter() - start) * 1000)

        size = out.stat().st_size
        duration = audio_duration_s(out)
        cost = len(phrase.text) * USD_PER_CHAR
        sample = Sample(
            provider=PROVIDER,
            voice=voice,
            phrase_id=phrase.id,
            file_path=str(out),
            file_size_bytes=size,
            duration_s=duration,
            latency_total_ms=latency_ms,
            cost_usd=cost,
            notes="local ONNX CPU",
        )
        append_metric(sample)
        print(f"  ✓ {phrase.id}  {latency_ms}ms  {size}B  {duration:.2f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
