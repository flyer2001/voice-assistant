#!/usr/bin/env python3
"""Проверка фильтра эха: python3 test_echo_filter.py

Эхо — это наш же TTS, который прозвучал на маке, попал в микрофон или в
дорожку системного звука и вернулся распознанным. Ломается это молча в две
стороны, обе проверяем: эхо, принятое за речь (мусор в конспекте и команды,
пришедшие в сессию как чужая реплика), и речь, принятая за эхо — потерянный
эфир.

Фикстуры синтетические, по форме реальных случаев: расшифровки рабочих
встреч приватные, в git им нельзя. Реальный корпус (194 TTS × 10 017 блоков)
мерит echo_baseline.py по /srv/voice-private.

Тесты держатся за контракт «эхо не инжектится, речь инжектится дословно», а
не за способ сравнения: ни порога, ни difflib в ассертах — иначе перейти на
другой алгоритм можно будет только вместе с переписыванием тестов.
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "ef", os.path.join(HERE, "echo_filter.py"))
ef = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ef)

# Длинная фраза агента — такие в проде и возвращались эхом.
TTS_LONG = ("Сергей, последний слой со снапшотом застейджен, проверки прошли. "
            "Коммить, описание пул реквеста в чате. Перед пулом нужен ребейз "
            "на девелоп.")

# Та же фраза, как её слышит микрофон через воздух: соседние реплики вокруг,
# искажения распознавания («девелон»), пропавшая запятая.
BLOCK_WITH_ECHO = (
    "В общем, все в одной задаче делаю, там недолго вроде. Если хочешь, надо "
    "обсудить контракт. Сергей, последний слой со снапшотом застейджен, "
    "проверки прошли. Комить, описание пул, реквесты в чате. Перед пулом нужен "
    "ребейс на девелон.")

# Живая речь: про тот же коммит и ревью говорят люди, своими словами.
BLOCK_REAL_SPEECH = (
    "Я докатил в пятницу задачку про возврат минзаказа в кнопках. Вмержено и "
    "раскачано даже на проде под АБ, если я правильно понял. Тогда я тоже "
    "гляну, проверю, что работает по АБ. Перед пулом ребейз делали?")


def _tts_dir(d, texts, age_s=0):
    """Папка в форме /srv/voice-out: json на каждую озвученную фразу."""
    for i, t in enumerate(texts):
        p = os.path.join(d, f"mac-work-fixture-{i}.json")
        with open(p, "w") as f:
            json.dump({"client_id": "mac-work", "text": t, "voice": "alena"}, f)
        if age_s:
            os.utime(p, (time.time() - age_s, time.time() - age_s))
    return d


def test_echo_detected():
    """Главный случай: фраза агента вернулась в блок через микрофон."""
    with tempfile.TemporaryDirectory() as d:
        _tts_dir(d, [TTS_LONG])
        assert ef.is_echo(BLOCK_WITH_ECHO, d)


def test_real_speech_kept():
    """Люди обсуждают тот же коммит — это эфир, а не эхо."""
    with tempfile.TemporaryDirectory() as d:
        _tts_dir(d, [TTS_LONG])
        assert not ef.is_echo(BLOCK_REAL_SPEECH, d)


def test_short_tts_never_matches():
    """Короткие фразы из частых слов набираются в любом тексте по кусочкам.

    На корпусе именно они дали верх ложных срабатываний («Слава ответил,
    смотри чат» — 0.83 на реплике, где человек говорит «Слава, прости»).
    Отличить их от речи нельзя, поэтому короткое эхо не фильтруем вовсе.
    """
    with tempfile.TemporaryDirectory() as d:
        _tts_dir(d, ["Слава ответил, смотри чат.", "Проверка задержки после правки."])
        assert not ef.is_echo(BLOCK_REAL_SPEECH, d)
        assert not ef.is_echo(
            "Слава, прости, я ещё маленечко задержу. Тогда смотри, у нас "
            "должна стартовать разработка, соответственно, до разработки я "
            "хотел проверить вот эту правку.", d)


def test_old_tts_ignored():
    """Произнесённое вне этого эфира эхом быть не может.

    Без окна по времени фильтр сравнивал TTS от сентября с записью октября —
    на корпусе это давало совпадения на 0.9 из чистого совпадения слов.
    """
    with tempfile.TemporaryDirectory() as d:
        _tts_dir(d, [TTS_LONG], age_s=6 * 3600)
        assert not ef.is_echo(BLOCK_WITH_ECHO, d)


def test_window_is_tunable():
    """Окно — ручка, а не константа: хвост отстаёт от эфира на минуты."""
    with tempfile.TemporaryDirectory() as d:
        _tts_dir(d, [TTS_LONG], age_s=6 * 3600)
        assert ef.is_echo(BLOCK_WITH_ECHO, d, window_s=7 * 3600)


def test_scattered_words_are_not_echo():
    """Те же слова россыпью по блоку — не эхо: эхо идёт сплошным куском."""
    shuffled = ("Коммить? Нужен ребейз. Снапшот проверим потом, описание "
                "допишем. Слой застейджен у Антона, пул реквеста пока нет, "
                "в чате Сергей просил проверки сначала прогнать на девелопе.")
    with tempfile.TemporaryDirectory() as d:
        _tts_dir(d, [TTS_LONG])
        assert not ef.is_echo(shuffled, d)


def test_empty_inputs():
    with tempfile.TemporaryDirectory() as d:
        _tts_dir(d, [TTS_LONG])
        assert not ef.is_echo("", d)
        assert not ef.is_echo("   ", d)


def test_no_tts_dir_is_not_echo():
    """TTS никто не озвучивал (или папка недоступна) — молча пропускаем эфир.

    Фильтр не вправе ронять транскрипцию: отсутствие данных для сверки
    значит «не эхо», а не «нечего писать».
    """
    assert not ef.is_echo(BLOCK_WITH_ECHO, "/nonexistent/voice-out")


def test_broken_json_does_not_crash():
    with tempfile.TemporaryDirectory() as d:
        _tts_dir(d, [TTS_LONG])
        with open(os.path.join(d, "mac-work-broken.json"), "w") as f:
            f.write("{не json")
        assert ef.is_echo(BLOCK_WITH_ECHO, d)


def test_cli_exit_codes():
    """Хвост зовёт фильтр из bash: 0 — эхо, 1 — эфир."""
    with tempfile.TemporaryDirectory() as d:
        _tts_dir(d, [TTS_LONG])
        for text, expected in ((BLOCK_WITH_ECHO, 0), (BLOCK_REAL_SPEECH, 1)):
            r = subprocess.run(
                [sys.executable, os.path.join(HERE, "echo_filter.py"),
                 "--tts-dir", d],
                input=text, capture_output=True, text=True, timeout=30)
            assert r.returncode == expected, (text[:40], r.returncode, r.stderr)


def test_cli_names_source_in_stderr():
    """В логе хвоста должно быть видно, чем именно блок признан эхом."""
    with tempfile.TemporaryDirectory() as d:
        _tts_dir(d, [TTS_LONG])
        r = subprocess.run(
            [sys.executable, os.path.join(HERE, "echo_filter.py"), "--tts-dir", d],
            input=BLOCK_WITH_ECHO, capture_output=True, text=True, timeout=30)
        assert "fixture-0.json" in r.stderr, r.stderr


def test_cli_never_prints_text():
    """Вердикт — кодом возврата. Текст блока наружу не выводим: его пишет
    хвост, и единственная копия не должна зависеть от этого процесса."""
    with tempfile.TemporaryDirectory() as d:
        _tts_dir(d, [TTS_LONG])
        r = subprocess.run(
            [sys.executable, os.path.join(HERE, "echo_filter.py"), "--tts-dir", d],
            input=BLOCK_WITH_ECHO, capture_output=True, text=True, timeout=30)
        assert r.stdout == "", r.stdout


if __name__ == "__main__":
    passed = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            passed += 1
            print(f"ok  {name}")
    print(f"\n{passed} passed")
