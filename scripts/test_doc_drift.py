#!/usr/bin/env python3
"""Проверка линтера расхождений в доках: python3 test_doc_drift.py

Дока расходится с реальностью молча: команда в ней остаётся рабочей на вид,
а правда уже в другом месте. 26.10 инспекция нашла шесть таких расхождений в
`~/.claude/docs/live-transcribe.md` (нянька писалась руками при живом
nanny.sh, остановка учила `pkill`, который гасит чужой эфир, чанк 15 против
обоснованного минимума 20). Разовая уборка это не чинит: разъехалось за три
недели и разъедется снова.

Линтер ловит три класса, и тесты держатся за них, а не за способ разбора:
запрещённая команда, несуществующий путь, расхождение значения env между
докой и скиллом.
"""
import importlib.util
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
LINT = os.path.join(HERE, "doc_drift.py")
spec = importlib.util.spec_from_file_location("dd", LINT)
dd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dd)


def _doc(d, name, text):
    p = os.path.join(d, name)
    with open(p, "w", encoding="utf-8") as f:
        f.write(text)
    return p


def test_banned_command_found():
    """Команда, которая гасит чужой эфир, не должна жить в инструкции."""
    with tempfile.TemporaryDirectory() as d:
        p = _doc(d, "doc.md", '## Остановка\n\n```bash\npkill -f "live_tail.sh mac-work"\n```\n')
        hits = dd.check_banned([p])
        assert len(hits) == 1, hits
        assert hits[0].line == 4, hits[0]
        assert "pid" in hits[0].message.lower(), hits[0].message


def test_tmux_launch_is_banned():
    """Хвост в tmux: сервер падает по памяти на VDS и уносит хвост (17.09)."""
    with tempfile.TemporaryDirectory() as d:
        p = _doc(d, "doc.md",
                 "```bash\ntmux new-session -d -s live-tail "
                 '"VOICE_CHUNK_S=30 ./live_tail.sh mac-work /srv/x"\n```\n')
        hits = dd.check_banned([p])
        assert len(hits) == 1 and "setsid" in hits[0].message, hits


def test_banned_allows_safe_commands():
    with tempfile.TemporaryDirectory() as d:
        p = _doc(d, "doc.md", "```bash\npgrep -af live_tail.sh\nkill 12345\n```\n")
        assert dd.check_banned([p]) == []


def test_banned_ignores_prose_about_the_ban():
    """Разбор грабли цитирует опасную команду — это не инструкция.

    Иначе линтер потребовал бы убрать объяснение, почему так нельзя, и знание
    о грабле исчезло бы вместе с предупреждением.
    """
    with tempfile.TemporaryDirectory() as d:
        p = _doc(d, "doc.md",
                 'Не делать так: `pkill -f "live_tail.sh mac-work"` — накроет\n'
                 "чужой хвост, гасить по pid.\n")
        assert dd.check_banned([p]) == []


def test_explanation_on_neighbour_line_suppresses_hit():
    """Запрет и цитата часто на разных строках — абзац читается целиком.

    После правки доки 26.10 линтер пометил собственное предупреждение: слово
    «накрывает» стояло строкой ниже цитаты `pkill`.
    """
    with tempfile.TemporaryDirectory() as d:
        p = _doc(d, "doc.md",
                 'Гасить по pid: шаблон `pkill -f "live_tail.sh mac-work"`\n'
                 "накрывает все хвосты на хосте, включая чужой рабочий.\n")
        assert dd.check_banned([p]) == []


def test_explanation_covers_word_forms():
    """Слово «накрывает» — та же грабля, что «накроет»: форма не должна решать.

    Первая версия знала только «накро» и пометила предупреждение со словом
    «накрывает» — то есть требовала убрать объяснение грабли.
    """
    with tempfile.TemporaryDirectory() as d:
        for word in ("накроет", "накрывает", "теряется", "не доезжает"):
            p = _doc(d, f"doc-{word[:5]}.md",
                     'Так нельзя делать — `pkill -f "live_tail.sh"`\n'
                     f"{word} не то, что нужно.\n")
            assert dd.check_banned([p]) == [], word


def test_missing_path_found():
    with tempfile.TemporaryDirectory() as d:
        p = _doc(d, "doc.md", "```bash\nbash /root/projects/voice/nope/missing.sh\n```\n")
        hits = dd.check_paths([p])
        assert len(hits) == 1 and "missing.sh" in hits[0].message, hits


def test_existing_path_ok():
    with tempfile.TemporaryDirectory() as d:
        p = _doc(d, "doc.md", f"```bash\npython3 {LINT}\n```\n")
        assert dd.check_paths([p]) == []


def test_home_paths_are_not_checked():
    """`~/Movies` живёт на маке, а не на VDS: проверить его отсюда нельзя.

    Первый прогон по живым докам дал шесть таких «находок» — это ложняки
    самого линтера, и они дороже пропусков: по ним начнут править доку.
    """
    with tempfile.TemporaryDirectory() as d:
        p = _doc(d, "doc.md", "```bash\nssh mac-work 'ls ~/Movies/*.mov'\n```\n")
        assert dd.check_paths([p]) == []


def test_env_value_strips_markdown():
    """`VOICE_ECHO_FILTER=1`, в тексте — значение 1, а не «1`,»."""
    with tempfile.TemporaryDirectory() as d:
        doc = _doc(d, "doc.md", "Выключатель `VOICE_ECHO_FILTER=1`, по умолчанию включён.\n")
        skill = _doc(d, "SKILL.md", "```bash\nVOICE_ECHO_FILTER=1 ./t.sh\n```\n")
        assert dd.check_env([doc], [skill]) == []


def test_env_mismatch_between_doc_and_skill():
    """Значение в доке разошлось со скиллом — скилл источник правды."""
    with tempfile.TemporaryDirectory() as d:
        doc = _doc(d, "doc.md", "```bash\nVOICE_CHUNK_S=15 VOICE_INJECT_EVERY=2 ./t.sh\n```\n")
        skill = _doc(d, "SKILL.md", "```bash\nVOICE_CHUNK_S=30 VOICE_INJECT_EVERY=1 ./t.sh\n```\n")
        hits = dd.check_env([doc], [skill])
        names = sorted(h.message.split("=")[0] for h in hits)
        assert names == ["VOICE_CHUNK_S", "VOICE_INJECT_EVERY"], hits


def test_env_match_is_quiet():
    with tempfile.TemporaryDirectory() as d:
        doc = _doc(d, "doc.md", "```bash\nVOICE_CHUNK_S=30 ./t.sh\n```\n")
        skill = _doc(d, "SKILL.md", "```bash\nVOICE_CHUNK_S=30 ./t.sh\n```\n")
        assert dd.check_env([doc], [skill]) == []


def test_env_placeholder_is_not_a_value():
    """`VOICE_INJECT_SID=<свой sid>` — заполняется человеком, сверять нечего."""
    with tempfile.TemporaryDirectory() as d:
        doc = _doc(d, "doc.md", "```bash\nVOICE_INJECT_SID=<свой happy sid> ./t.sh\n```\n")
        skill = _doc(d, "SKILL.md", "```bash\nVOICE_INJECT_SID=<свой sid> ./t.sh\n```\n")
        assert dd.check_env([doc], [skill]) == []


def test_cli_exit_code_and_report():
    """Линтер зовут из cron: 0 — чисто, 1 — есть расхождения, список в stdout."""
    with tempfile.TemporaryDirectory() as d:
        bad = _doc(d, "bad.md", '```bash\npkill -f "live_tail.sh mac-work"\n```\n')
        r = subprocess.run([sys.executable, LINT, "--doc", bad],
                           capture_output=True, text=True, timeout=60)
        assert r.returncode == 1, r.stdout
        assert "bad.md:2" in r.stdout, r.stdout

        good = _doc(d, "good.md", "Ничего опасного.\n")
        r = subprocess.run([sys.executable, LINT, "--doc", good],
                           capture_output=True, text=True, timeout=60)
        assert r.returncode == 0, r.stdout


def test_cli_counts_are_the_metric():
    """Метрика «стало лучше» — число расхождений в выводе, его читает cron."""
    with tempfile.TemporaryDirectory() as d:
        bad = _doc(d, "bad.md",
                   '```bash\npkill -f "live_tail.sh mac-work"\n'
                   "bash /root/projects/voice/nope/missing.sh\n```\n")
        r = subprocess.run([sys.executable, LINT, "--doc", bad],
                           capture_output=True, text=True, timeout=60)
        assert "расхождений: 2" in r.stdout, r.stdout


if __name__ == "__main__":
    passed = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            passed += 1
            print(f"ok  {name}")
    print(f"\n{passed} passed")
