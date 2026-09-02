#!/usr/bin/env python3
"""Проверка счётной части конвейера: python3 test_transcribe_chunks.py

Распознавание не трогаем — проверяем то, что ломается молча: порядок чанков,
пропуск того, в который ffmpeg ещё пишет, таймкоды и запрет записи без
подтверждения.
"""
import importlib.util
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "tc", os.path.join(HERE, "transcribe_chunks.py"))
tc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tc)


def _mkchunks(d, names):
    for n in names:
        open(os.path.join(d, n), "w").close()


def test_ready_skips_last():
    """Последний чанк ещё пишется — распознавать его рано."""
    with tempfile.TemporaryDirectory() as d:
        _mkchunks(d, ["chunk-000.wav", "chunk-001.wav", "chunk-002.wav"])
        assert [i for i, _ in tc.ready_chunks(d)] == [0, 1]


def test_ready_sorts_numerically():
    """Сортировка по числу, не по строке: иначе chunk-10 встанет перед chunk-9."""
    with tempfile.TemporaryDirectory() as d:
        _mkchunks(d, [f"chunk-{i:03d}.wav" for i in (0, 9, 10, 11)])
        assert [i for i, _ in tc.ready_chunks(d)] == [0, 9, 10]


def test_ready_ignores_foreign_files():
    with tempfile.TemporaryDirectory() as d:
        _mkchunks(d, ["chunk-000.wav", "chunk-001.wav",
                      "live.md", ".DS_Store", "notes.txt"])
        assert [i for i, _ in tc.ready_chunks(d)] == [0]


def test_ready_empty_dir():
    with tempfile.TemporaryDirectory() as d:
        assert tc.ready_chunks(d) == []


def test_ready_single_chunk_not_ready():
    """Один чанк — он же последний, значит ещё пишется."""
    with tempfile.TemporaryDirectory() as d:
        _mkchunks(d, ["chunk-000.wav"])
        assert tc.ready_chunks(d) == []


def test_stamp_counts_from_start():
    assert tc.stamp(0, 30) == "00:00:00"
    assert tc.stamp(1, 30) == "00:00:30"
    assert tc.stamp(2, 30) == "00:01:00"


def test_stamp_crosses_hour():
    """Доклад длиннее часа — таймкод не должен сбрасываться."""
    assert tc.stamp(120, 30) == "01:00:00"
    assert tc.stamp(241, 30) == "02:00:30"


def test_stamp_respects_chunk_length():
    assert tc.stamp(2, 60) == "00:02:00"


def test_header_written_once():
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "live.md")

        class A:
            title = "Доклад"
            consent = False
        tc.write_header(out, A)
        tc.write_header(out, A)
        assert open(out).read().count("# Доклад") == 1


def test_header_records_consent():
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "live.md")

        class A:
            title = "Созвон"
            consent = True
        tc.write_header(out, A)
        assert "Участники предупреждены о записи: да" in open(out).read()


def test_refuses_without_consent():
    """Режим с чужими голосами не должен стартовать молча."""
    with tempfile.TemporaryDirectory() as d:
        r = subprocess.run(
            [sys.executable, os.path.join(HERE, "transcribe_chunks.py"),
             d, os.path.join(d, "live.md"), "--require-consent"],
            capture_output=True, text=True, timeout=30)
        assert r.returncode != 0, "должен был отказаться"
        assert "участники предупреждены" in r.stderr.lower(), r.stderr
        assert not os.path.exists(os.path.join(d, "live.md")), \
            "файл не должен создаваться при отказе"


if __name__ == "__main__":
    passed = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            passed += 1
            print(f"ok  {name}")
    print(f"\n{passed} passed")
