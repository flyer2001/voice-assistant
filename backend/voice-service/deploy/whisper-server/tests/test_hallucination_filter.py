"""Фильтр галлюцинаций whisper: мусор с дейлика 2026-10-23 режется, речь цела.

Запуск: python3 tests/test_hallucination_filter.py (из каталога whisper-server).
Без pytest намеренно — на ubuntu-home в venv только faster-whisper и FastAPI.
"""
import re
from collections import Counter
from pathlib import Path

SRC = Path(__file__).resolve().parent.parent / "server.py"
_src = SRC.read_text()
_ns = {"re": re, "Counter": Counter}
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
