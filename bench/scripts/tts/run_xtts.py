#!/usr/bin/env python3
"""XTTS-v2 local (coqui-tts) — neural multilingual, voice cloning.

First run downloads ~2GB model into ~/.local/share/tts/. Voice cloning
requires a reference WAV; we use coqui's built-in speakers (Claribel Dervla
female, etc.). Multilingual: lang='ru' for RU, 'en' for EN, model handles
code-mixing within one utterance when lang is set per request.
"""
from __future__ import annotations

import os
import sys
import time
from pathlib import Path

from lib import (
    Sample,
    append_metric,
    audio_duration_s,
    load_corpus,
    sample_path,
)

PROVIDER = "xtts-v2"
DEFAULT_VOICE = "Claribel Dervla"   # female English-bias multilingual speaker
MODEL = "tts_models/multilingual/multi-dataset/xtts_v2"

USD_PER_CHAR = 0.0


def main() -> int:
    voice = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_VOICE
    os.environ["COQUI_TOS_AGREED"] = "1"

    from TTS.api import TTS  # type: ignore

    tts = TTS(model_name=MODEL, progress_bar=False)

    for phrase in load_corpus():
        out = sample_path(PROVIDER, voice.replace(" ", "_"), phrase.id, "wav")
        # XTTS supports per-call language. Map our categories → language code.
        lang = "en" if phrase.category == "codemix_tech" else "ru"
        try:
            start = time.perf_counter()
            tts.tts_to_file(
                text=phrase.text,
                speaker=voice,
                language=lang,
                file_path=str(out),
            )
            latency_ms = int((time.perf_counter() - start) * 1000)
        except Exception as e:
            print(f"  ✗ {phrase.id}  {type(e).__name__}: {str(e)[:160]}")
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
            notes=f"local M1 CPU, model={MODEL.split('/')[-1]}, lang={lang}",
        )
        append_metric(sample)
        print(f"  ✓ {phrase.id}  {latency_ms}ms  {size}B  {duration:.2f}s  lang={lang}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
