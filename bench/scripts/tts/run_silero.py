#!/usr/bin/env python3
"""Silero TTS v4_ru — local PyTorch, multi-speaker.

Downloads model (~50MB) into ~/.cache/torch/hub on first run. Voices:
aidar (м), baya (ж), kseniya (ж), xenia (ж), eugene (м), random.
"""
from __future__ import annotations

import sys
import time
from pathlib import Path

import soundfile as sf
import torch

from lib import (
    Sample,
    append_metric,
    audio_duration_s,
    load_corpus,
    sample_path,
)

PROVIDER = "silero"
DEFAULT_VOICE = "baya"   # f, RU
SAMPLE_RATE = 48000
LANGUAGE = "ru"
MODEL_ID = "v4_ru"

USD_PER_CHAR = 0.0


def main() -> int:
    voice = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_VOICE

    torch.hub.set_dir(str(Path.home() / ".cache" / "torch" / "hub"))
    device = torch.device("cpu")  # silero v4_ru is fast on CPU; M1 Metal path is fiddly

    model, _ = torch.hub.load(
        repo_or_dir="snakers4/silero-models",
        model="silero_tts",
        language=LANGUAGE,
        speaker=MODEL_ID,
        trust_repo=True,
    )
    model.to(device)

    for phrase in load_corpus():
        out = sample_path(PROVIDER, voice, phrase.id, "wav")
        try:
            start = time.perf_counter()
            audio = model.apply_tts(
                text=phrase.text,
                speaker=voice,
                sample_rate=SAMPLE_RATE,
            )
            sf.write(str(out), audio.cpu().numpy(), SAMPLE_RATE)
            latency_ms = int((time.perf_counter() - start) * 1000)
        except (ValueError, RuntimeError) as e:
            # Silero v4_ru rejects text it cannot phonemize (often pure-EN or
            # mixed sentences with unmapped chars). Record as failed sample.
            print(f"  ✗ {phrase.id}  {type(e).__name__}: {str(e)[:120]}")
            continue

        size = out.stat().st_size
        duration = audio_duration_s(out)
        sample = Sample(
            provider=PROVIDER,
            voice=voice,
            phrase_id=phrase.id,
            file_path=str(out),
            file_size_bytes=size,
            duration_s=duration,
            latency_total_ms=latency_ms,
            cost_usd=0.0,
            notes=f"local torch CPU, model={MODEL_ID}",
        )
        append_metric(sample)
        print(f"  ✓ {phrase.id}  {latency_ms}ms  {size}B  {duration:.2f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
