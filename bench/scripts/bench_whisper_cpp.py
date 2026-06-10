"""bench_whisper_cpp.py — STT бенчмарк через whisper.cpp CLI (Metal на Mac, CPU/CUDA elsewhere).

Использует whisper.cpp бинарь (`whisper-cli` или legacy `main`) и парсит его JSON
output. Дополняет HW monitoring через monitor.py.

Setup на mac-home:
    brew install whisper-cpp
    # или from source: git clone + make WHISPER_METAL=1

Usage:
    python bench_whisper_cpp.py \\
        --model large-v3 \\
        --audio-dir ../../assets/bench/normalized \\
        --codec clean \\
        --output ../results/2026-06-09-whispercpp-large-mac.csv \\
        --runs 3
"""

from __future__ import annotations

import argparse
import csv
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from monitor import HardwareMonitor  # noqa: E402


# Map of friendly model names → whisper.cpp ggml model filenames.
MODEL_FILES = {
    "tiny": "ggml-tiny.bin",
    "base": "ggml-base.bin",
    "small": "ggml-small.bin",
    "medium": "ggml-medium.bin",
    "large-v3": "ggml-large-v3.bin",
    "large-v3-turbo": "ggml-large-v3-turbo.bin",
}


def find_binary(explicit: str | None = None) -> str:
    """Look for whisper-cli or legacy. PATH + standard brew locations (handles non-interactive SSH)."""
    if explicit:
        if Path(explicit).exists():
            return explicit
        print(f"ERR: explicit binary not found: {explicit}", file=sys.stderr)
        sys.exit(1)
    for name in ("whisper-cli", "whisper", "main"):
        p = shutil.which(name)
        if p:
            return p
    for candidate in ("/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli"):
        if Path(candidate).exists():
            return candidate
    print("ERR: whisper.cpp binary not found. Try --binary /path/to/whisper-cli", file=sys.stderr)
    sys.exit(1)


def find_model(model_name: str, models_dir: Path) -> Path:
    """Look for ggml file in expected locations."""
    filename = MODEL_FILES.get(model_name, f"ggml-{model_name}.bin")
    candidates = [
        models_dir / filename,
        Path.home() / ".cache" / "whisper.cpp" / filename,
        Path("/opt/homebrew/share/whisper-cpp") / filename,
        Path("/usr/local/share/whisper-cpp") / filename,
    ]
    for c in candidates:
        if c.exists():
            return c
    print(f"ERR: model {filename} not found in:", file=sys.stderr)
    for c in candidates:
        print(f"  - {c}", file=sys.stderr)
    print("  Download: `./models/download-ggml-model.sh large-v3` in whisper.cpp dir", file=sys.stderr)
    sys.exit(1)


def parse_whisper_output(stdout: str) -> str:
    """Extract transcribed text from whisper.cpp stdout (timestamps stripped)."""
    lines = []
    for line in stdout.splitlines():
        # Lines like: "[00:00:00.000 --> 00:00:05.000]   текст"
        if line.startswith("[") and "]" in line:
            text = line.split("]", 1)[1].strip()
            if text:
                lines.append(text)
    return " ".join(lines)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--model", required=True, help="model name: tiny/base/small/medium/large-v3/large-v3-turbo")
    p.add_argument("--audio-dir", required=True)
    p.add_argument("--codec", required=True, choices=["clean", "gsm"])
    p.add_argument("--output", required=True)
    p.add_argument("--runs", type=int, default=3)
    p.add_argument("--language", default="ru")
    p.add_argument("--models-dir", default="./models", help="path with ggml-*.bin files")
    p.add_argument("--threads", type=int, default=8)
    p.add_argument("--binary", default=None, help="explicit path to whisper-cli (overrides PATH lookup)")
    args = p.parse_args()

    binary = find_binary(args.binary)
    model_path = find_model(args.model, Path(args.models_dir).resolve())
    audio_dir = Path(args.audio_dir).resolve()
    wav_files = sorted(audio_dir.glob("*.wav"))
    if not wav_files:
        print(f"ERR: no .wav in {audio_dir}", file=sys.stderr)
        sys.exit(1)

    print(f"Binary: {binary}")
    print(f"Model: {args.model} ({model_path}), files: {len(wav_files)}, runs: {args.runs}")

    # Warm-up
    print("Warm-up...")
    subprocess.run(
        [binary, "-m", str(model_path), "-l", args.language, "-t", str(args.threads), "-f", str(wav_files[0])],
        capture_output=True,
        timeout=120,
    )

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    is_new = not out_path.exists()
    fieldnames = [
        "model", "file", "codec", "run",
        "text", "latency_ms",
        "ram_peak_mb", "ram_avg_mb", "cpu_avg_pct", "cpu_peak_pct",
        "vram_peak_mb", "vram_avg_mb", "gpu_util_avg_pct", "gpu_util_peak_pct",
        "gpu_power_avg_w", "gpu_temp_max_c",
        "binary", "threads",
    ]

    with open(out_path, "a" if not is_new else "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        if is_new:
            w.writeheader()

        for wav in wav_files:
            for run in range(1, args.runs + 1):
                with HardwareMonitor(interval_s=0.5) as mon:
                    t0 = time.monotonic()
                    proc = subprocess.run(
                        [binary, "-m", str(model_path), "-l", args.language,
                         "-t", str(args.threads), "-f", str(wav), "-nt"],  # -nt: no timestamps
                        capture_output=True,
                        text=True,
                        timeout=120,
                    )
                    latency_ms = (time.monotonic() - t0) * 1000

                # Without -nt we'd parse; with -nt stdout is just text
                text = proc.stdout.strip()
                if not text and proc.stdout:
                    text = parse_whisper_output(proc.stdout)

                metrics = mon.summary()
                row = {
                    "model": args.model,
                    "file": wav.name,
                    "codec": args.codec,
                    "run": run,
                    "text": text,
                    "latency_ms": round(latency_ms, 2),
                    "binary": Path(binary).name,
                    "threads": args.threads,
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
