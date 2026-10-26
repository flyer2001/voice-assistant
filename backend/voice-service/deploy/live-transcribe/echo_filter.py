#!/usr/bin/env python3
"""Эхо своего же TTS в транскрипции: отличить от живой речи.

Агент озвучивает ответ на маке (`voice-mac-reply-both`), звук попадает в
дорожку системного звука или в микрофон OBS, whisper распознаёт его обратно, и
в конспект приходит блок, который выглядит как чужая реплика. За три недели так
просочилось семь блоков; 26.10 среди них были «коммить», «ребейз на девелоп» и
«можно пушить» — то есть команды, пришедшие в сессию по неаутентифицированному
каналу (разбор — OPERATIONS.md, «Эхо TTS»).

Вердикт — кодом возврата: 0 эхо, 1 эфир. Текст наружу не печатаем, его пишет
хвост; фильтр ничего не удаляет и не правит, эхо-блок остаётся в конспекте под
меткой. Ошибиться в сторону «это эфир» дешевле, чем потерять минуту записи,
поэтому любое сомнение — не эхо.

Пороги ниже подобраны на корпусе (194 TTS × 10 017 блоков,
`echo_baseline.py`), а не на глаз: coverage сам по себе давал ложные
срабатывания 0.8–0.9 на коротких фразах из частых слов.
"""
import argparse
import glob
import json
import os
import re
import sys
import time
from difflib import SequenceMatcher

VOICE_OUT = "/srv/voice-out"

# Хвост отстаёт от живого эфира на 2-4 минуты, плюс чанк до 60 с — 10 минут с
# запасом. Произнесённое раньше в этот эфир попасть не могло.
WINDOW_S = 600

# Эхо идёт сплошным куском: whisper коверкает слова, но не переставляет их.
# Случайное совпадение такой длины на корпусе не встретилось ни раза, а вот
# сумма мелких совпадений давала 0.8-0.9 на коротких фразах из частых слов
# («Слава ответил, смотри чат» против реплики «Слава, прости, я задержу»).
# Отдельного порога на длину фразы нет сознательно: короткая физически не даёт
# сплошного куска такой длины, и на корпусе он ничего не менял.
MIN_RUN = 40

# Доля фразы, найденная в блоке. Вторая половина проверки: длинный кусок плюс
# общее совпадение, иначе цитата внутри живой речи сошла бы за эхо.
MIN_COVERAGE = 0.5


def norm(s):
    s = s.lower().replace("ё", "е")
    s = re.sub(r"[^а-яa-z0-9 ]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def recent_tts(tts_dir, window_s):
    """Озвученные фразы за окно: (имя файла, нормализованный текст).

    Время берём по mtime на этой машине — файл пишется в момент озвучки, так
    что часовые пояса мака и VDS в расчёт не входят.
    """
    now = time.time()
    out = []
    for p in sorted(glob.glob(os.path.join(tts_dir, "*.json"))):
        try:
            if now - os.path.getmtime(p) > window_s:
                continue
            with open(p) as f:
                text = json.load(f).get("text") or ""
        except (OSError, ValueError, json.JSONDecodeError):
            continue
        n = norm(text)
        if n:
            out.append((os.path.basename(p), n))
    return out


def match(tts_norm, block_norm):
    """(длина самого длинного сплошного совпадения, доля совпавшего)."""
    m = SequenceMatcher(None, tts_norm, block_norm, autojunk=False)
    run = m.find_longest_match(0, len(tts_norm), 0, len(block_norm)).size
    cov = sum(b.size for b in m.get_matching_blocks()) / len(tts_norm)
    return run, cov


def find_echo(text, tts_dir=VOICE_OUT, window_s=WINDOW_S):
    """Чем именно блок признан эхом, или None."""
    bn = norm(text or "")
    if not bn:
        return None
    for name, tn in recent_tts(tts_dir, window_s):
        run, cov = match(tn, bn)
        if run >= MIN_RUN and cov >= MIN_COVERAGE:
            return name, run, cov
    return None


def is_echo(text, tts_dir=VOICE_OUT, window_s=WINDOW_S):
    return find_echo(text, tts_dir, window_s) is not None


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--tts-dir", default=VOICE_OUT)
    ap.add_argument("--window", type=int, default=WINDOW_S,
                    help="окно в секундах, в котором TTS считается свежим")
    a = ap.parse_args()

    hit = find_echo(sys.stdin.read(), a.tts_dir, a.window)
    if hit:
        name, run, cov = hit
        print(f"эхо TTS: {name} (кусок {run} симв., совпало {cov:.0%})",
              file=sys.stderr)
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
