"""bench_longform.py — long-form (15-30 min) STT bench для одного audio файла.

Runs:
- faster-whisper large-v3-turbo (1 model, N runs)
- faster-whisper large-v3 (1 model, N runs)
- google/gemma-3n-E2B-it с 30-sec chunking (1 model, N runs)

CSV format (long-format, one row per (model, run)):
  model, file, run, text, latency_ms, chunk_count,
  model_load_ms, ram_peak_mb, vram_peak_mb, device, dtype

Usage:
    python bench_longform.py \\
        --audio assets/long-form-bench/en/stack-overflow-agents.wav \\
        --output bench/results/longform-2026-06-11.csv \\
        --runs 3 \\
        --language en \\
        --models whisper-turbo,whisper-large,gemma-3n-E2B

Cross-platform: works на Win (CUDA), Mac (MPS/CPU), Linux (CUDA/CPU).
"""

from __future__ import annotations

import argparse
import csv
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from monitor import HardwareMonitor  # noqa: E402


FIELDNAMES = [
    "model", "file", "run",
    "text", "latency_ms", "chunk_count",
    "model_load_ms",
    "ram_peak_mb", "ram_avg_mb", "cpu_avg_pct",
    "vram_peak_mb", "vram_avg_mb", "gpu_util_avg_pct",
    "gpu_power_avg_w", "gpu_temp_max_c",
    "device", "dtype",
]


def _faster_whisper_load(model_name: str, device: str):
    from faster_whisper import WhisperModel
    compute_type = "float16" if device == "cuda" else "int8"
    return WhisperModel(model_name, device=device, compute_type=compute_type), compute_type


def _faster_whisper_infer(model, audio_path: str, language: str) -> str:
    segments, _ = model.transcribe(audio_path, language=language)
    return " ".join(s.text for s in segments).strip()


def _gemma_load(model_id: str, device: str):
    import torch
    from transformers import AutoProcessor, AutoModelForImageTextToText
    # Gemma 3n has weights outside fp16 range — use bfloat16 on CUDA/MPS
    dtype = torch.bfloat16 if device in ("cuda", "mps") else torch.float32
    processor = AutoProcessor.from_pretrained(model_id, trust_remote_code=True)
    model = AutoModelForImageTextToText.from_pretrained(
        model_id, torch_dtype=dtype, device_map=device, trust_remote_code=True,
    )
    model.eval()
    dtype_str = {torch.float16: "float16", torch.bfloat16: "bfloat16", torch.float32: "float32"}[dtype]
    return (processor, model), dtype_str


def _gemma_chunked_infer(processor, model, audio_path: str, language: str,
                         chunk_sec: int = 29, overlap_sec: int = 1) -> tuple[str, int]:
    """Split audio into 30-sec chunks, transcribe each, concat.

    Gemma 3n trained на ≤30 sec clips → strict limit. Use 29s window with 1s overlap.

    Returns (transcript, chunk_count).
    """
    import librosa
    import torch

    lang_word = {"en": "English", "ru": "Russian"}.get(language, "English")
    prompt = f"Transcribe the following speech in {lang_word}."

    audio, _ = librosa.load(audio_path, sr=16000, mono=True)
    sr = 16000
    chunk_samples = chunk_sec * sr
    step_samples = (chunk_sec - overlap_sec) * sr

    segments = []
    chunk_count = 0
    for start in range(0, len(audio), step_samples):
        chunk = audio[start : start + chunk_samples]
        if len(chunk) < sr * 2:  # skip tails shorter than 2 sec
            break
        messages = [{
            "role": "user",
            "content": [
                {"type": "audio", "audio": chunk},
                {"type": "text", "text": prompt},
            ],
        }]
        inputs = processor.apply_chat_template(
            messages, add_generation_prompt=True,
            tokenize=True, return_dict=True, return_tensors="pt",
        ).to(model.device)
        input_len = inputs["input_ids"].shape[1]
        with torch.no_grad():
            out_ids = model.generate(**inputs, max_new_tokens=300, do_sample=False)
        seg = processor.decode(out_ids[0][input_len:], skip_special_tokens=True).strip()
        segments.append(seg)
        chunk_count += 1

    return " ".join(segments), chunk_count


def detect_device() -> str:
    try:
        import torch
        if torch.cuda.is_available():
            return "cuda"
        if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            return "mps"
    except ImportError:
        pass
    return "cpu"


def run_model(spec: str, audio_path: str, language: str, runs: int, device: str):
    """Returns list of CSV row dicts."""
    rows = []

    if spec == "whisper-turbo":
        model_name = "large-v3-turbo"
        print(f"\n=== {model_name} (faster-whisper, {device}) ===")
        t0 = time.monotonic()
        with HardwareMonitor(interval_s=0.5) as load_mon:
            model, compute_type = _faster_whisper_load(model_name, device)
        load_ms = (time.monotonic() - t0) * 1000
        load_metrics = load_mon.summary()
        print(f"  loaded in {load_ms:.0f} ms")

        # warm up
        print("  warm-up...")
        _faster_whisper_infer(model, audio_path, language)

        for run in range(1, runs + 1):
            with HardwareMonitor(interval_s=0.5) as mon:
                t_inf = time.monotonic()
                text = _faster_whisper_infer(model, audio_path, language)
                latency_ms = (time.monotonic() - t_inf) * 1000
            metrics = mon.summary()
            print(f"  run {run}: {latency_ms/1000:.1f}s, text {len(text)} chars, peak VRAM {metrics.get('vram_peak_mb', 0):.0f}MB")
            rows.append(_row(model_name, audio_path, run, text, latency_ms, None, load_ms, metrics, device, compute_type))

        del model
        return rows

    if spec == "whisper-large":
        model_name = "large-v3"
        print(f"\n=== {model_name} (faster-whisper, {device}) ===")
        t0 = time.monotonic()
        with HardwareMonitor(interval_s=0.5) as load_mon:
            model, compute_type = _faster_whisper_load(model_name, device)
        load_ms = (time.monotonic() - t0) * 1000
        load_metrics = load_mon.summary()
        print(f"  loaded in {load_ms:.0f} ms")

        print("  warm-up...")
        _faster_whisper_infer(model, audio_path, language)

        for run in range(1, runs + 1):
            with HardwareMonitor(interval_s=0.5) as mon:
                t_inf = time.monotonic()
                text = _faster_whisper_infer(model, audio_path, language)
                latency_ms = (time.monotonic() - t_inf) * 1000
            metrics = mon.summary()
            print(f"  run {run}: {latency_ms/1000:.1f}s, text {len(text)} chars, peak VRAM {metrics.get('vram_peak_mb', 0):.0f}MB")
            rows.append(_row(model_name, audio_path, run, text, latency_ms, None, load_ms, metrics, device, compute_type))

        del model
        return rows

    if spec == "gemma-3n-E2B":
        model_id = "google/gemma-3n-E2B-it"
        print(f"\n=== {model_id} (HF chunked, {device}) ===")
        t0 = time.monotonic()
        with HardwareMonitor(interval_s=0.5) as load_mon:
            (processor, model), dtype_str = _gemma_load(model_id, device)
        load_ms = (time.monotonic() - t0) * 1000
        load_metrics = load_mon.summary()
        print(f"  loaded in {load_ms:.0f} ms")

        print("  warm-up (1 chunk equivalent)...")
        # warm-up: just first 29 sec chunk
        import librosa
        audio_head, _ = librosa.load(audio_path, sr=16000, mono=True, duration=29)
        _ = _gemma_chunked_infer.__wrapped__ if hasattr(_gemma_chunked_infer, "__wrapped__") else None
        # cheap warm-up — single chunk via reuse of code path
        messages = [{
            "role": "user",
            "content": [
                {"type": "audio", "audio": audio_head},
                {"type": "text", "text": "Transcribe the following speech in English."},
            ],
        }]
        inputs = processor.apply_chat_template(
            messages, add_generation_prompt=True, tokenize=True,
            return_dict=True, return_tensors="pt",
        ).to(model.device)
        import torch
        with torch.no_grad():
            _ = model.generate(**inputs, max_new_tokens=50, do_sample=False)

        for run in range(1, runs + 1):
            with HardwareMonitor(interval_s=1.0) as mon:
                t_inf = time.monotonic()
                text, chunk_count = _gemma_chunked_infer(processor, model, audio_path, language)
                latency_ms = (time.monotonic() - t_inf) * 1000
            metrics = mon.summary()
            print(f"  run {run}: {latency_ms/1000:.1f}s, {chunk_count} chunks, text {len(text)} chars, peak VRAM {metrics.get('vram_peak_mb', 0):.0f}MB")
            rows.append(_row(model_id, audio_path, run, text, latency_ms, chunk_count, load_ms, metrics, device, dtype_str))

        del model, processor
        return rows

    raise ValueError(f"unknown model spec: {spec}")


def _row(model_name, audio_path, run, text, latency_ms, chunk_count, load_ms, metrics, device, dtype):
    row = {
        "model": model_name,
        "file": Path(audio_path).name,
        "run": run,
        "text": text,
        "latency_ms": round(latency_ms, 2),
        "chunk_count": chunk_count if chunk_count is not None else "",
        "model_load_ms": round(load_ms, 2),
        "device": device,
        "dtype": dtype,
    }
    for k in ("ram_peak_mb", "ram_avg_mb", "cpu_avg_pct",
              "vram_peak_mb", "vram_avg_mb", "gpu_util_avg_pct",
              "gpu_power_avg_w", "gpu_temp_max_c"):
        v = metrics.get(k)
        row[k] = round(v, 2) if v is not None else ""
    return row


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--audio", required=True, help="path to long-form .wav (16kHz mono)")
    p.add_argument("--output", required=True, help="output CSV path")
    p.add_argument("--runs", type=int, default=3)
    p.add_argument("--language", default="en")
    p.add_argument("--models", default="whisper-turbo,whisper-large,gemma-3n-E2B",
                   help="comma-separated: whisper-turbo,whisper-large,gemma-3n-E2B")
    p.add_argument("--device", default=None)
    args = p.parse_args()

    audio_path = str(Path(args.audio).resolve())
    if not Path(audio_path).exists():
        print(f"ERR: audio not found: {audio_path}", file=sys.stderr)
        sys.exit(1)

    device = args.device or detect_device()
    print(f"Audio: {audio_path}")
    print(f"Device: {device}")
    print(f"Models: {args.models}")
    print(f"Runs per model: {args.runs}")

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    is_new = not out_path.exists()
    with open(out_path, "a" if not is_new else "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=FIELDNAMES)
        if is_new:
            w.writeheader()
        f.flush()

        for spec in args.models.split(","):
            spec = spec.strip()
            if not spec:
                continue
            try:
                rows = run_model(spec, audio_path, args.language, args.runs, device)
            except Exception as e:
                print(f"ERR running {spec}: {e}", file=sys.stderr)
                import traceback; traceback.print_exc()
                continue
            for row in rows:
                w.writerow(row)
                f.flush()

    print(f"\nOutput: {out_path}")


if __name__ == "__main__":
    main()
