#!/usr/bin/env python3
"""Проверка счётной части: python3 test_run.py

Без фреймворка. Сеть и файлы не трогаем — тестируем чистые функции,
на которых держатся цифры в отчёте.
"""
import importlib.util
import os

spec = importlib.util.spec_from_file_location(
    "run", os.path.join(os.path.dirname(os.path.abspath(__file__)), "run.py"))
run = importlib.util.module_from_spec(spec)
spec.loader.exec_module(run)


def test_wer_identical():
    assert run.wer(["а", "б", "в"], ["а", "б", "в"]) == (0, 3)


def test_wer_substitution():
    assert run.wer(["а", "б", "в"], ["а", "х", "в"]) == (1, 3)


def test_wer_deletion():
    assert run.wer(["а", "б"], ["а"]) == (1, 2)


def test_wer_insertion():
    assert run.wer(["а"], ["а", "б"]) == (1, 1)


def test_wer_empty_hypothesis():
    """STT промолчал — все слова эталона потеряны, не деление на ноль."""
    assert run.wer(["а", "б", "в"], []) == (3, 3)


def test_wer_empty_reference():
    """Пустой эталон: ошибок столько, сколько лишних слов, ref_len=0.

    Отчёт обязан пропускать такие строки, иначе делит на ноль.
    """
    assert run.wer([], ["а", "б"]) == (2, 0)


def test_wer_real_case():
    """msg 262: «Веронись к диспетчеру» против «Вернись к диспетчеру»."""
    ref = run.normalize("Вернись к диспетчеру")
    hyp = run.normalize("Веронись к диспетчеру.")
    errors, n = run.wer(ref, hyp)
    assert (errors, n) == (1, 3), (errors, n)


def test_normalize_strips_punctuation_and_case():
    assert run.normalize("Вернись, к Диспетчеру!") == ["вернись", "к", "диспетчеру"]


def test_normalize_yo_folding():
    """ё/е — разное написание одного слова, не ошибка распознавания."""
    assert run.normalize("ЁЖ") == run.normalize("еж") == ["еж"]


def test_normalize_none():
    assert run.normalize(None) == []


def test_normalize_keeps_latin_and_digits():
    """Техтермины и цифры — то, ради чего этот бенчмарк и нужен."""
    assert run.normalize("focus на voice-сессии 60s") == [
        "focus", "на", "voice", "сессии", "60s"]


if __name__ == "__main__":
    passed = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            passed += 1
            print(f"ok  {name}")
    print(f"\n{passed} passed")
