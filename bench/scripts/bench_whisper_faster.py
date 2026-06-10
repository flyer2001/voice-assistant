"""bench_whisper_faster.py — STT бенчмарк через faster-whisper (CUDA или CPU).

Прогоняет audio файлы через указанную Whisper модель N повторов,
собирает (text, latency, HW metrics) в CSV.

Usage:
    python bench_whisper_faster.py \\
        --model large-v3 \\
        --audio-dir ../../assets/bench/normalized \\
        --codec clean \\
        --output ../results/2026-06-09-whisper-large-clean.csv \\
        --runs 3

Cross-platform: works on Win (CUDA), Mac (CPU/MPS), Linux (CUDA/CPU).
"""

from __future__ import annotations

import argparse
import csv
import os
import sys
import time
from pathlib import Path

# allow importing monitor from same dir
sys.path.insert(0, str(Path(__file__).parent))
from monitor import HardwareMonitor  # noqa: E402

try:
    from faster_whisper import WhisperModel
except ImportError:
    print("ERR: faster-whisper required (pip install faster-whisper)", file=sys.stderr)
    sys.exit(1)


def detect_device() -> tuple[str, str]:
    """Returns (device, compute_type) — CUDA если доступна, иначе CPU."""
    try:
        import torch
        if torch.cuda.is_available():
            return "cuda", "float16"
    except ImportError:
        pass
    return "cpu", "int8"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--model", required=True, help="faster-whisper model: tiny/base/small/medium/large-v3/large-v3-turbo")
    p.add_argument("--audio-dir", required=True, help="directory with .wav files")
    p.add_argument("--codec", required=True, choices=["clean", "gsm"], help="for CSV row tagging")
    p.add_argument("--output", required=True, help="output CSV path")
    p.add_argument("--runs", type=int, default=3, help="repetitions per file (warm latency)")
    p.add_argument("--language", default="ru", help="ISO 639-1 lang code")
    p.add_argument("--device", default=None, help="cuda / cpu / auto (default: auto)")
    args = p.parse_args()

    audio_dir = Path(args.audio_dir).resolve()
    wav_files = sorted(audio_dir.glob("*.wav"))
    if not wav_files:
        print(f"ERR: no .wav files in {audio_dir}", file=sys.stderr)
        sys.exit(1)

    device, compute_type = (args.device, "float16" if args.device == "cuda" else "int8") if args.device else detect_device()
    print(f"Model: {args.model}, device: {device} ({compute_type}), files: {len(wav_files)}, runs: {args.runs}")

    print("Loading model...")
    t_load_start = time.monotonic()
    with HardwareMonitor(interval_s=0.5) as load_mon:
        model = WhisperModel(args.model, device=device, compute_type=compute_type)
    load_ms = (time.monotonic() - t_load_start) * 1000
    load_metrics = load_mon.summary()
    print(f"  loaded in {load_ms:.0f} ms, peak RAM {load_metrics.get('ram_peak_mb', 0):.0f} MB"
          + (f", peak VRAM {load_metrics.get('vram_peak_mb', 0):.0f} MB" if load_metrics.get("vram_peak_mb") else ""))

    # Warm-up: run on first file to load CUDA kernels, JIT, etc.
    print("Warm-up run on", wav_files[0].name, "...")
    list(model.transcribe(str(wav_files[0]), language=args.language)[0])

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    is_new = not out_path.exists()
    fieldnames = [
        "model", "file", "codec", "run",
        "text", "latency_ms",
        "ram_peak_mb", "ram_avg_mb", "cpu_avg_pct", "cpu_peak_pct",
        "vram_peak_mb", "vram_avg_mb", "gpu_util_avg_pct", "gpu_util_peak_pct",
        "gpu_power_avg_w", "gpu_temp_max_c",
        "model_load_ms", "model_load_ram_peak_mb", "model_load_vram_peak_mb",
        "device", "compute_type",
    ]

    with open(out_path, "a" if not is_new else "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        if is_new:
            w.writeheader()

        for wav in wav_files:
            for run in range(1, args.runs + 1):
                with HardwareMonitor(interval_s=0.5) as mon:
                    t0 = time.monotonic()
                    segments, info = model.transcribe(str(wav), language=args.language)
                    text = " ".join(s.text for s in segments).strip()
                    latency_ms = (time.monotonic() - t0) * 1000
                metrics = mon.summary()
                row = {
                    "model": args.model,
                    "file": wav.name,
                    "codec": args.codec,
                    "run": run,
                    "text": text,
                    "latency_ms": round(latency_ms, 2),
                    "model_load_ms": round(load_ms, 2),
                    "model_load_ram_peak_mb": round(load_metrics.get("ram_peak_mb") or 0, 1),
                    "model_load_vram_peak_mb": round(load_metrics.get("vram_peak_mb") or 0, 1),
                    "device": device,
                    "compute_type": compute_type,
                }
                for k in ("ram_peak_mb", "ram_avg_mb", "cpu_avg_pct", "cpu_peak_pct",
                         "vram_peak_mb", "vram_avg_mb", "gpu_util_avg_pct", "gpu_util_peak_pct",
                         "gpu_power_avg_w", "gpu_temp_max_c"):
                    v = metrics.get(k)
                    row[k] = round(v, 2) if v is not None else ""
                w.writerow(row)
                f.flush()
                print(f"  [{wav.name} run={run}] {latency_ms:.0f}ms — {text[:60]}{'...' if len(text) > 60 else ''}")

    print(f"\nOutput: {out_path}")


if __name__ == "__main__":
    main()
