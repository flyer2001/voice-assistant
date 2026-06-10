"""bench_gemma_hf.py — Gemma 3n/4 audio STT через HuggingFace Transformers.

Прогоняет audio через Gemma audio-enabled model в ASR режиме. Cross-platform
(CUDA + MPS + CPU автоматически).

Models to try (parametrized via --model):
  - google/gemma-3n-E2B-it      (~5GB на диск, ~2GB VRAM)
  - google/gemma-3n-E4B-it      (~7GB на диск, ~3GB VRAM)
  - google/gemma-4-E2B-it       (release март 2026, if available)
  - google/gemma-4-E4B-it       (если в HF Hub)
  - google/gemma-4-12B-Unified  (mac-home only, 32GB RAM нужен)

Prompt structure (per Apple Gemma docs):
    Transcribe the following speech segment in Russian into Russian text.
    Follow these specific instructions for formatting the answer:
    * Only output the transcription, with no newlines.
    * When transcribing numbers, write the digits, i.e. write 1.7 and not one point seven.

Usage:
    python bench_gemma_hf.py \\
        --model google/gemma-3n-E2B-it \\
        --audio-dir ../../assets/bench/normalized \\
        --codec clean \\
        --output ../results/2026-06-09-gemma-3n-e2b-clean.csv \\
        --runs 3
"""

from __future__ import annotations

import argparse
import csv
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from monitor import HardwareMonitor  # noqa: E402

try:
    import torch
    from transformers import AutoProcessor, AutoModelForCausalLM
except ImportError as e:
    print(f"ERR: {e}. Install: pip install torch transformers accelerate", file=sys.stderr)
    sys.exit(1)

try:
    import librosa
except ImportError:
    print("ERR: librosa required (pip install librosa)", file=sys.stderr)
    sys.exit(1)


ASR_PROMPT_RU = (
    "Transcribe the following speech segment in Russian into Russian text. "
    "Follow these specific instructions for formatting the answer:\n"
    "* Only output the transcription, with no newlines.\n"
    "* When transcribing numbers, write the digits, i.e. write 1.7 and not one point seven, and write 3 instead of three.\n"
    "* Preserve English technical terms as they are pronounced (e.g. GitHub, pull request)."
)


def detect_device() -> str:
    if torch.cuda.is_available():
        return "cuda"
    if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
        return "mps"
    return "cpu"


def load_audio(path: Path) -> "tuple[np.ndarray, int]":
    """Load 16kHz mono float32. librosa автоматически resample/downmix."""
    audio, sr = librosa.load(str(path), sr=16000, mono=True)
    return audio, sr


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--model", required=True, help="HF model id, e.g. google/gemma-3n-E2B-it")
    p.add_argument("--audio-dir", required=True)
    p.add_argument("--codec", required=True, choices=["clean", "gsm"])
    p.add_argument("--output", required=True)
    p.add_argument("--runs", type=int, default=3)
    p.add_argument("--device", default=None, help="cuda / mps / cpu / auto")
    p.add_argument("--dtype", default=None, help="float16 / bfloat16 / float32")
    args = p.parse_args()

    device = args.device or detect_device()
    dtype_str = args.dtype or ("float16" if device == "cuda" else "bfloat16" if device == "mps" else "float32")
    dtype = {"float16": torch.float16, "bfloat16": torch.bfloat16, "float32": torch.float32}[dtype_str]

    audio_dir = Path(args.audio_dir).resolve()
    wav_files = sorted(audio_dir.glob("*.wav"))
    if not wav_files:
        print(f"ERR: no .wav in {audio_dir}", file=sys.stderr)
        sys.exit(1)

    print(f"Model: {args.model}, device: {device} ({dtype_str}), files: {len(wav_files)}")

    print("Loading processor + model...")
    t_load = time.monotonic()
    with HardwareMonitor(interval_s=0.5) as load_mon:
        processor = AutoProcessor.from_pretrained(args.model, trust_remote_code=True)
        model = AutoModelForCausalLM.from_pretrained(
            args.model,
            torch_dtype=dtype,
            device_map=device,
            trust_remote_code=True,
        )
        model.eval()
    load_ms = (time.monotonic() - t_load) * 1000
    load_metrics = load_mon.summary()
    print(f"  loaded in {load_ms:.0f} ms, peak RAM {load_metrics.get('ram_peak_mb', 0):.0f} MB"
          + (f", peak VRAM {load_metrics.get('vram_peak_mb', 0):.0f} MB" if load_metrics.get("vram_peak_mb") else ""))

    # Warm-up на первом файле
    print("Warm-up on", wav_files[0].name, "...")
    audio, _ = load_audio(wav_files[0])
    with torch.no_grad():
        inputs = processor(text=ASR_PROMPT_RU, audio=audio, return_tensors="pt").to(device)
        _ = model.generate(**inputs, max_new_tokens=200, do_sample=False)

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    is_new = not out_path.exists()
    fieldnames = [
        "model", "file", "codec", "run",
        "text", "latency_ms",
        "ram_peak_mb", "ram_avg_mb", "cpu_avg_pct", "cpu_peak_pct",
        "vram_peak_mb", "vram_avg_mb", "gpu_util_avg_pct", "gpu_util_peak_pct",
        "gpu_power_avg_w", "gpu_temp_max_c",
        "model_load_ms", "device", "dtype",
    ]

    with open(out_path, "a" if not is_new else "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        if is_new:
            w.writeheader()

        for wav in wav_files:
            audio, _ = load_audio(wav)
            for run in range(1, args.runs + 1):
                with HardwareMonitor(interval_s=0.5) as mon:
                    t0 = time.monotonic()
                    with torch.no_grad():
                        inputs = processor(text=ASR_PROMPT_RU, audio=audio, return_tensors="pt").to(device)
                        output_ids = model.generate(**inputs, max_new_tokens=200, do_sample=False)
                        text = processor.decode(output_ids[0], skip_special_tokens=True)
                    latency_ms = (time.monotonic() - t0) * 1000

                # Strip the prompt prefix from text if present
                if ASR_PROMPT_RU in text:
                    text = text.split(ASR_PROMPT_RU, 1)[1].strip()

                metrics = mon.summary()
                row = {
                    "model": args.model,
                    "file": wav.name,
                    "codec": args.codec,
                    "run": run,
                    "text": text,
                    "latency_ms": round(latency_ms, 2),
                    "model_load_ms": round(load_ms, 2),
                    "device": device,
                    "dtype": dtype_str,
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
