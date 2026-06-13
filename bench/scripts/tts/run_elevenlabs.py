#!/usr/bin/env python3
"""ElevenLabs Multilingual v2 — generate samples for the corpus."""
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

PROVIDER = "elevenlabs"
MODEL_ID = "eleven_multilingual_v2"
DEFAULT_VOICE = "Bella"
VOICE_IDS = {
    "Bella": "EXAVITQu4vr4xnSDxMaL",
    "Rachel": "21m00Tcm4TlvDq8ikWAM",
    "Sarah": "EXAVITQu4vr4xnSDxMaL",  # same as Bella historically
}

# Pay-as-you-go list price as of 2026-06; Starter/Creator pre-paid are cheaper
# per 1k chars but the marginal $/char number stays stable for comparisons.
USD_PER_CHAR = 0.00018

ENV_FILE = "elevenlabs.env"


def synth(api_key: str, voice_id: str, text: str, out_path: Path) -> int:
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"
    headers = {
        "xi-api-key": api_key,
        "Content-Type": "application/json",
        "Accept": "audio/mpeg",
    }
    body = {
        "text": text,
        "model_id": MODEL_ID,
        "voice_settings": {"stability": 0.5, "similarity_boost": 0.75},
    }
    start = time.perf_counter()
    # curl_cffi impersonates Chrome's TLS fingerprint — bypasses Cloudflare
    # bot challenges that block plain `requests` / `httpx`.
    resp = curl_requests.post(
        url, headers=headers, json=body, timeout=60, impersonate="chrome120"
    )
    if resp.status_code != 200:
        raise RuntimeError(f"HTTP {resp.status_code}: {resp.text[:200]}")
    out_path.write_bytes(resp.content)
    return int((time.perf_counter() - start) * 1000)


def main() -> int:
    voice = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_VOICE
    voice_id = VOICE_IDS.get(voice)
    if not voice_id:
        print(f"unknown voice '{voice}' (known: {list(VOICE_IDS)})", file=sys.stderr)
        return 2

    if maybe_load_proxy():
        print("  (using HTTP_PROXY from ~/.config/voice-bench/proxy.env)")
    env = read_env(ENV_FILE)
    api_key = env.get("API-KEY") or env.get("API_KEY")
    if not api_key:
        print(f"no API-KEY in {ENV_FILE}", file=sys.stderr)
        return 1

    for phrase in load_corpus():
        out = sample_path(PROVIDER, voice, phrase.id, "mp3")
        try:
            latency_ms = synth(api_key, voice_id, phrase.text, out)
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
            notes=f"model={MODEL_ID}",
        )
        append_metric(sample)
        print(f"  ✓ {phrase.id}  {latency_ms}ms  {sample.file_size_bytes}B  {duration:.2f}s  ${cost:.5f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
