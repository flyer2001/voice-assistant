#!/usr/bin/env python3
"""Диаризация wav: кто говорит и когда. Запускается на ubuntu-home.

    diarize-venv/bin/python diarize.py chunk.wav > segments.json

Отдаёт JSON-список {start, end, speaker} в секундах, отсортированный по времени.
Имён не знает и знать не может — только номера Speaker_00, Speaker_01.
Сопоставление с людьми делает вызывающая сторона.

Почему sherpa-onnx, а не pyannote: pyannote тянет torch (~2.5 ГБ) и gated-модель
с HF-токеном и ручным принятием лицензии. Здесь два onnx-файла на 35 МБ, ничего
не gated, и GPU не нужен — сорок минут считаются быстрее, чем их слушать.
"""

from __future__ import annotations

import argparse
import json
import sys
import wave
from pathlib import Path

import numpy as np
import sherpa_onnx

MODELS = Path("/mnt/win-share/Users/Serg/diarize-models")
SEG = MODELS / "sherpa-onnx-pyannote-segmentation-3-0" / "model.onnx"
EMB = MODELS / "3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx"


def read_wav(path: Path) -> tuple[np.ndarray, int]:
    with wave.open(str(path), "rb") as w:
        if w.getnchannels() != 1 or w.getsampwidth() != 2:
            raise SystemExit(f"{path}: нужен mono 16-бит wav, а тут "
                             f"{w.getnchannels()} кан. / {w.getsampwidth() * 8} бит")
        rate = w.getframerate()
        raw = w.readframes(w.getnframes())
    return np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0, rate


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("wav")
    # Число говорящих. Знаешь точно — передай, кластеризация станет устойчивее.
    # По умолчанию -1: подбирается сам по порогу, на дейлике состав плавает.
    ap.add_argument("--num-speakers", type=int, default=-1)
    # Порог склейки кластеров. Больше — меньше спикеров (склеит похожие голоса),
    # меньше — больше (разорвёт одного человека на двух). 0.5 — дефолт автора.
    ap.add_argument("--threshold", type=float, default=0.5)
    args = ap.parse_args()

    for m in (SEG, EMB):
        if not m.exists():
            raise SystemExit(f"нет модели {m} — см. docs/diarization.md")

    samples, rate = read_wav(Path(args.wav))

    config = sherpa_onnx.OfflineSpeakerDiarizationConfig(
        segmentation=sherpa_onnx.OfflineSpeakerSegmentationModelConfig(
            pyannote=sherpa_onnx.OfflineSpeakerSegmentationPyannoteModelConfig(
                model=str(SEG)
            ),
        ),
        embedding=sherpa_onnx.SpeakerEmbeddingExtractorConfig(model=str(EMB)),
        clustering=sherpa_onnx.FastClusteringConfig(
            num_clusters=args.num_speakers, threshold=args.threshold
        ),
        # Короче 0.3 с — обычно «ага» и вздохи, они только плодят спикеров.
        min_duration_on=0.3,
        min_duration_off=0.5,
    )
    sd = sherpa_onnx.OfflineSpeakerDiarization(config)
    if sd.sample_rate != rate:
        raise SystemExit(f"модель ждёт {sd.sample_rate} Гц, а wav {rate} Гц")

    result = sd.process(samples).sort_by_start_time()
    json.dump(
        [
            {"start": round(s.start, 2), "end": round(s.end, 2),
             "speaker": f"Speaker_{s.speaker:02d}"}
            for s in result
        ],
        sys.stdout,
        ensure_ascii=False,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
