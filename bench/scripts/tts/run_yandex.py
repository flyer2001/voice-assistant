#!/usr/bin/env python3
"""Yandex SpeechKit v3 TTS — generate samples for the corpus.

Uses Yandex Cloud SpeechKit synchronous synthesis endpoint.
Docs: https://aistudio.yandex.ru/docs/ru/speechkit/tts/
"""
from __future__ import annotations

import sys
import time
from pathlib import Path

from curl_cffi import requests as curl_requests

from lib import (
    Sample,
    append_metric,
    audio_duration_s,
    load_corpus,
    maybe_load_proxy,
    read_env,
    sample_path,
)

PROVIDER = "yandex"
DEFAULT_VOICE = "alena"
DEFAULT_ROLE = "neutral"

# v3 sync endpoint accepts JSON, returns base64-encoded OGG Opus chunks.
# v1 endpoint is simpler — accepts form-encoded, returns raw audio. Use v1
# for the bench: less moving parts, same audio quality for our 7-phrase set.
V1_URL = "https://tts.api.cloud.yandex.net/speech/v1/tts:synthesize"

# Pricing on aistudio.yandex.ru (2026 ru-prod tariff): generic ~250 RUB / 1M chars
# (~$2.7), premium ~600 RUB / 1M chars (~$6.5). Use generic ru price for parity.
USD_PER_CHAR = 0.0000027

ENV_FILE = "yandex_speechkit.env"


def synth(api_key: str, voice: str, text: str, out_path: Path) -> int:
    headers = {
        "Authorization": f"Api-Key {api_key}",
    }
    data = {
        "text": text,
        "voice": voice,
        "lang": "ru-RU",
        "format": "mp3",
        "folderId": "",  # ignored when authenticating with API key
    }
    start = time.perf_counter()
    resp = curl_requests.post(
        V1_URL, headers=headers, data=data, timeout=60, impersonate="chrome120"
    )
    if resp.status_code != 200:
        raise RuntimeError(f"HTTP {resp.status_code}: {resp.text[:300]}")
    ct = resp.headers.get("Content-Type", "")
    if "audio" not in ct.lower():
        raise RuntimeError(f"Unexpected content-type: {ct}, body: {resp.text[:200]}")
    out_path.write_bytes(resp.content)
    return int((time.perf_counter() - start) * 1000)


def main() -> int:
    voice = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_VOICE
    maybe_load_proxy()
    env = read_env(ENV_FILE)
    api_key = env.get("API-KEY") or env.get("API_KEY")
    if not api_key:
        print(f"no API-KEY in {ENV_FILE}", file=sys.stderr)
        return 1

    for phrase in load_corpus():
        out = sample_path(PROVIDER, voice, phrase.id, "mp3")
        try:
            latency_ms = synth(api_key, voice, phrase.text, out)
        except Exception as e:
            print(f"  ✗ {phrase.id}  {type(e).__name__}: {str(e)[:200]}")
            continue
        cost = len(phrase.text) * USD_PER_CHAR
        duration = audio_duration_s(out)
        sample = Sample(
            provider=PROVIDER,
            voice=voice,
            phrase_id=phrase.id,
            file_path=str(out),
            file_size_bytes=out.stat().st_size,
            duration_s=duration,
            latency_total_ms=latency_ms,
            cost_usd=round(cost, 6),
            notes=f"v1 sync, lang=ru-RU",
        )
        append_metric(sample)
        print(f"  ✓ {phrase.id}  {latency_ms}ms  {sample.file_size_bytes}B  {duration:.2f}s  ${cost:.5f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
