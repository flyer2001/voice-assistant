"""Фильтр галлюцинаций whisper: мусор с дейлика 2026-10-23 режется, речь цела.

Запуск: python3 tests/test_hallucination_filter.py (из каталога whisper-server).
Без pytest намеренно — на ubuntu-home в venv только faster-whisper и FastAPI.
"""
import array
import math
import re
import wave
from collections import Counter
from pathlib import Path  # noqa: E402 — нужен и тесту гейта

SRC = Path(__file__).resolve().parent.parent / "server.py"
_src = SRC.read_text()
_ns = {"re": re, "Counter": Counter, "wave": wave, "math": math, "array": array.array}
# Исполняем только блок фильтра: импорт server.py тянет загрузку модели на CUDA.
exec(_src[_src.index("_CREDITS = re.compile"):_src.index('print(f"loading model')], _ns)
clean_segment = _ns["clean_segment"]

PROMPT = (
    "Рабочий созвон команды: дейлик, груминг. Задачи в трекере вида GNRL-79942. "
    "Имена: Сергей, Лёша, Слава, Коля, Макс, Антон, Соня, Юля, Аглара, Габриэль, Саша."
)

DROP = [
    "Субтитры делал DimaTorzok",
    "Редактор субтитров А.Семкин Корректор А.Егорова",
    "Продолжение следует...",
    "Важно. Важно. Важно. Важно. За год. Важно. Важно.",
    "Лёша, Слава, Коля, Габриэль, Саша.",
]

KEEP = [
    "Поэтому я их разом катну. Поэтому это пока ready for release.",
    "Ага, Слава, спасибо.",
    "Да, да, да.",
    "Я пока до шторки не добралась, сегодня вернусь к ней.",
]

for text in DROP:
    assert clean_segment(text, PROMPT) == "", f"не отбраковано: {text}"
for text in KEEP:
    assert clean_segment(text, PROMPT) == text, f"съело живую речь: {text}"
print(f"ok: {len(DROP)} drop / {len(KEEP)} keep")

# --- входной гейт по громкости -------------------------------------------
import tempfile

dbfs = _ns["dbfs"]


def _wav(path: str, amplitude: int, seconds: float = 0.5, rate: int = 16000) -> None:
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        n = int(rate * seconds)
        frames = bytearray()
        for i in range(n):
            v = int(amplitude * math.sin(2 * math.pi * 440 * i / rate))
            frames += int(v).to_bytes(2, "little", signed=True)
        w.writeframes(bytes(frames))


with tempfile.TemporaryDirectory() as d:
    silent, loud, faint = f"{d}/s.wav", f"{d}/l.wav", f"{d}/f.wav"
    _wav(silent, 0)
    _wav(loud, 3000)      # примерно −24 dBFS — речь
    _wav(faint, 20)       # примерно −61 dBFS — тишина в комнате
    assert dbfs(silent) == -120.0, dbfs(silent)
    assert -30 < dbfs(loud) < -18, dbfs(loud)
    assert dbfs(faint) < -55, dbfs(faint)
    # Порог по умолчанию: речь проходит, фон нет.
    assert dbfs(loud) > -55 > dbfs(faint)
    # Не-wav на входе гейт не ломает, а пропускает дальше.
    Path(f"{d}/x.bin").write_bytes(b"not a wav")
    assert dbfs(f"{d}/x.bin") is None

print("ok: гейт по громкости")
