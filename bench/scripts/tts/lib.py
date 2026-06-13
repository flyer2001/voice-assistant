"""Shared utilities for TTS bench scripts."""
from __future__ import annotations

import csv
import json
import os
import time
from dataclasses import dataclass, asdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
CORPUS_PATH = Path(__file__).parent / "corpus.json"
RESULTS_ROOT = REPO / "bench" / "results" / "tts"
METRICS_CSV = RESULTS_ROOT / "metrics.csv"


@dataclass
class Phrase:
    id: str
    text: str
    category: str
    purpose: str


@dataclass
class Sample:
    """One audio file produced by one provider/voice for one phrase."""
    provider: str
    voice: str
    phrase_id: str
    file_path: str
    file_size_bytes: int
    duration_s: float
    latency_total_ms: int
    cost_usd: float
    notes: str = ""


def load_corpus() -> list[Phrase]:
    with CORPUS_PATH.open() as f:
        data = json.load(f)
    return [Phrase(**p) for p in data["phrases"]]


ENV_SEARCH_PATHS = [
    Path.home() / ".config" / "voice-bench",
    Path("/etc"),
]


def maybe_load_proxy() -> bool:
    """If ~/.config/voice-bench/proxy.env exists, export HTTP_PROXY/HTTPS_PROXY
    into the process env so `requests` routes outbound calls through it.
    Needed on mac-home where ElevenLabs / many cloud APIs are RU geo-blocked."""
    try:
        proxy_env = _parse_env_file(Path.home() / ".config" / "voice-bench" / "proxy.env")
    except FileNotFoundError:
        return False
    for k, v in proxy_env.items():
        os.environ.setdefault(k, v)
    return True


def read_env(filename: str) -> dict[str, str]:
    """Parse KEY=VALUE env file. Accepts keys with '-' in name (not POSIX-shell-safe).
    `filename` is a bare basename (e.g. 'elevenlabs.env'); searched in
    ~/.config/voice-bench/ then /etc/."""
    candidate_paths = [d / filename for d in ENV_SEARCH_PATHS]
    for path in candidate_paths:
        if path.is_file():
            return _parse_env_file(path)
    raise FileNotFoundError(
        f"{filename} not found in: {', '.join(str(p) for p in candidate_paths)}"
    )


def _parse_env_file(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    with path.open() as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def provider_dir(provider: str, voice: str) -> Path:
    d = RESULTS_ROOT / provider / voice
    d.mkdir(parents=True, exist_ok=True)
    return d


def sample_path(provider: str, voice: str, phrase_id: str, ext: str) -> Path:
    return provider_dir(provider, voice) / f"{phrase_id}.{ext}"


def append_metric(s: Sample) -> None:
    RESULTS_ROOT.mkdir(parents=True, exist_ok=True)
    new = not METRICS_CSV.exists()
    with METRICS_CSV.open("a", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(asdict(s).keys()))
        if new:
            w.writeheader()
        w.writerow(asdict(s))


def time_block():
    """Context manager-like timer. Use: t = time_block(); ...; ms = t()"""
    start = time.perf_counter()
    return lambda: int((time.perf_counter() - start) * 1000)


def audio_duration_s(path: Path) -> float:
    """Probe duration via soundfile (fallback ffprobe)."""
    try:
        import soundfile as sf

        info = sf.info(str(path))
        return float(info.duration)
    except Exception:
        import subprocess

        out = subprocess.run(
            [
                "ffprobe",
                "-v",
                "error",
                "-show_entries",
                "format=duration",
                "-of",
                "default=noprint_wrappers=1:nokey=1",
                str(path),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        try:
            return float(out.stdout.strip())
        except Exception:
            return 0.0
