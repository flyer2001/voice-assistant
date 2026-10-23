"""Whisper STT relay for voice-assistant backend.

Endpoint:
  POST /transcribe
    multipart: audio (file), lang_hint (str, optional)
  Response 200 JSON:
    {text, lang, duration_s, stt_ms}

  GET /health → {ok: true, model: ..., device: ...}
"""
from __future__ import annotations

import os
import re
import tempfile
import time
from collections import Counter
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from faster_whisper import WhisperModel

MODEL_ID = os.environ.get("WHISPER_MODEL_ID", "mobiuslabsgmbh/faster-whisper-large-v3-turbo")
DEVICE = os.environ.get("WHISPER_DEVICE", "cuda")
COMPUTE_TYPE = os.environ.get("WHISPER_COMPUTE_TYPE", "float16")

# Подсказка со словарём домена. Принимается от клиента в форме.
#
# ПО УМОЛЧАНИЮ ПУСТА — намеренно. Прогон 2026-08-01
# (voice/bench/whisper-accuracy/comparison-2026-08-01.md) показал, что на
# этой модели (turbo) промпт даёт 2 улучшения и 2 регресса из 24 клипов.
# Опасен именно характер регресса: распознавание "примагничивается" к
# словам из словаря — "Фокусируйся на voice.sess" стало "на voice-agent",
# потому что voice-agent есть в списке. Для голосовых команд переключения
# фокуса это хуже, чем исходная ошибка.
#
# На large-v3 (mac-агент) тот же промпт улучшил 15 клипов из 24 — там он
# включён и оправдан. Поэтому решение оставлено за клиентом, а не зашито
# в сервер: WHISPER_INITIAL_PROMPT=<текст> включает default осознанно.
DEFAULT_INITIAL_PROMPT = os.environ.get("WHISPER_INITIAL_PROMPT", "")

# Фильтр галлюцинаций. Дейлик 2026-10-23 дал три вида мусора на тихих
# кусках: титры обучающего корпуса («Субтитры делал DimaTorzok», «Редактор
# субтитров А.Семкин»), repetition loop («Важно. Важно. Важно… За год.») и
# соскальзывание языка. Первые два детерминированы и режутся на выходе,
# третий лечится condition_on_previous_text=False ниже.
_CREDITS = re.compile(
    r"субтитр|корректор\s+[А-Я]\.|продолжение\s+следует|dimatorzok|"
    r"спасибо\s+за\s+просмотр|подписывайтесь|amara\.org|titlovi|opensubtitles",
    re.IGNORECASE,
)


def _is_loop(text: str, min_words: int = 6, ratio: float = 0.5, reps: int = 4) -> bool:
    """Одно слово повторено reps+ раз И уникальных слов мало.

    Оба условия вместе: живая речь тоже сыпет «вот… вот… вот», но у неё
    доля уникальных слов остаётся высокой.
    """
    words = re.findall(r"\w+", text.lower())
    if len(words) < min_words:
        return False
    return max(Counter(words).values()) >= reps and len(set(words)) / len(words) < ratio


def _is_prompt_echo(text: str, prompt: str | None) -> bool:
    """Перечисление из трёх+ слов, все из промпта, — это промпт протёк.

    На тишине модель вместо титров выдаёт список имён из initial_prompt
    («Лёша, Слава, Коля, Габриэль, Саша»). Условие узкое намеренно: нужна
    и запятая через каждое слово, и полное попадание в промпт.
    """
    if not prompt:
        return False
    parts = [p.strip().lower() for p in text.strip().rstrip(".").split(",")]
    if len(parts) < 3 or any(len(p.split()) != 1 for p in parts):
        return False
    if len(set(parts)) != len(parts):  # «да, да, да» — речь, не перечисление
        return False
    vocab = set(re.findall(r"\w+", prompt.lower()))
    return all(p in vocab for p in parts if p)


def clean_segment(text: str, prompt: str | None = None) -> str:
    """Пустая строка = сегмент выброшен как галлюцинация."""
    t = text.strip()
    if not t or _CREDITS.search(t) or _is_loop(t) or _is_prompt_echo(t, prompt):
        return ""
    return t


print(f"loading model {MODEL_ID} on {DEVICE}/{COMPUTE_TYPE}...")
_load_start = time.time()
model = WhisperModel(MODEL_ID, device=DEVICE, compute_type=COMPUTE_TYPE)
print(f"model loaded in {time.time() - _load_start:.1f}s")

app = FastAPI(title="whisper-relay", version="0.1")


@app.get("/health")
async def health():
    return {
        "ok": True,
        "model": MODEL_ID,
        "device": DEVICE,
        "compute_type": COMPUTE_TYPE,
        "default_prompt_len": len(DEFAULT_INITIAL_PROMPT),
    }


@app.post("/transcribe")
async def transcribe(
    audio: UploadFile = File(...),
    lang_hint: str = Form(""),
    initial_prompt: str = Form(""),
):
    audio_bytes = await audio.read()
    if not audio_bytes:
        raise HTTPException(status_code=400, detail="empty audio")

    suffix = Path(audio.filename or "rec").suffix or ".bin"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as f:
        f.write(audio_bytes)
        tmp_path = f.name

    start = time.time()
    try:
        prompt = initial_prompt or DEFAULT_INITIAL_PROMPT or None
        segments, info = model.transcribe(
            tmp_path,
            language=lang_hint or None,
            initial_prompt=prompt,
            vad_filter=True,
            # Без этого декодер тащит свой предыдущий вывод в следующий
            # сегмент и зацикливается на тихих кусках.
            condition_on_previous_text=False,
            # Порог «тут нет речи» выше дефолтных 0.6: тихая дорожка
            # микрофона (−60 dB на дейлике) иначе превращается в титры.
            no_speech_threshold=0.7,
            compression_ratio_threshold=2.4,
            log_prob_threshold=-1.0,
        )
        kept = [c for c in (clean_segment(s.text, prompt) for s in segments) if c]
        text = " ".join(kept).strip()
        elapsed_ms = int((time.time() - start) * 1000)
        return JSONResponse(
            {
                "text": text,
                "lang": info.language,
                "duration_s": float(info.duration),
                "stt_ms": elapsed_ms,
                "prompt_used": bool(prompt),
            }
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"whisper error: {e}") from e
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


if __name__ == "__main__":
    import uvicorn

    port = int(os.environ.get("WHISPER_PORT", "8000"))
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")
