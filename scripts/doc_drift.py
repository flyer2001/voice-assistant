#!/usr/bin/env python3
"""Расхождения доки с реальностью: запрещённые команды, мёртвые пути, env.

Повод — инспекция 26.10 (`docs/inspection-live-transcribe-duplication.md`):
`~/.claude/docs/live-transcribe.md` за три недели разошлась с репо в шести
местах, и каждое выглядело рабочей инструкцией. Уборка руками это не держит,
поэтому проверка автоматическая и годится в cron.

    python3 doc_drift.py                 # доки и скиллы live-транскрипции
    python3 doc_drift.py --doc FILE ...  # произвольные файлы

Код возврата: 0 — чисто, 1 — есть расхождения. Их число в последней строке:
это и есть метрика, по которой видно, стало лучше или хуже.

Линтер намеренно тупой и знает только три класса. Смысловые дубли он не
ловит — это работа человека (и повод для инспекции), а не регулярки.
"""
import argparse
import os
import re
import sys
from collections import namedtuple

Hit = namedtuple("Hit", "path line message")

VOICE = "/root/projects/voice"
DEFAULT_DOCS = [
    os.path.expanduser("~/.claude/docs/live-transcribe.md"),
    f"{VOICE}/docs/live-transcribe.md",
    f"{VOICE}/backend/voice-service/deploy/live-transcribe/OPERATIONS.md",
]
DEFAULT_SKILLS = [
    f"{VOICE}/.claude/skills/prepare-to-rec/SKILL.md",
    f"{VOICE}/.claude/skills/meeting-digest/SKILL.md",
]

# Команды, которых в инструкции быть не должно, и чем их заменить. Третий
# элемент — что должно найтись в окне вокруг строки: так ловится случай,
# растянутый на несколько строк (нянька циклом), не порождая по находке на
# каждую строку окна.
BANNED = [
    (re.compile(r"pkill\s+-f\s+[\"']?live_tail"), None,
     "pkill по шаблону гасит ВСЕ хвосты на хосте, включая чужой рабочий "
     "(проверено 26.10: два хвоста с разными sid, шаблон видит оба) — "
     "гасить по pid со сверкой VOICE_INJECT_SID через ps eww"),
    (re.compile(r"pkill\s+-f\s+[\"']?nanny\.sh"), None,
     "pkill -f nanny.sh убивает сам вызывающий Bash — шаблон [n]anny"),
    (re.compile(r"while\s+true"), re.compile(r"live_tail"),
     "своя нянька циклом не нужна: в репо есть nanny.sh, а правило "
     "CLAUDE.md требует сторожа hb, а не самописного"),
    (re.compile(r"tmux\s+new-session"), re.compile(r"live_tail|live-tail"),
     "хвост в tmux не поднимать: tmux-сервер падает при нехватке памяти на "
     "VDS и уносит хвост с собой (17.09) — setsid nohup переживает и смерть "
     "tmux, и закрытие сессии"),
    (re.compile(r"inject\.mjs"), re.compile(r"спящ"),
     "inject в спящую сессию не доезжает (inject.mjs: no running session) — "
     "спящей сессии пишут в inbox"),
]

# Строка объясняет грабли, а не велит так делать: цитату опасной команды в
# разборе трогать нельзя, иначе предупреждение придётся удалить вместе с ней.
EXPLAINING = re.compile(
    r"не\s+(делать|годится|применять|подход|доед|доезж)|нельзя|накр[оы]|"
    r"убива|вместо|теряет|⚠️|опасн", re.IGNORECASE)

# Только абсолютные пути этой машины. `~/...` в доках почти всегда мак
# (`~/Movies`, `~/Library`), проверить его отсюда нельзя, а ложная находка
# дороже пропуска: по ней начнут править доку.
PATH_RE = re.compile(r"(?<![\w/~])(/root/projects/[\w./-]+)")
ENV_RE = re.compile(r"\b(VOICE_[A-Z0-9_]+)=([^\s`'\"]+)")
PLACEHOLDER = re.compile(r"^[<$\"']|^\$\(")


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read().splitlines()
    except OSError:
        return None


def check_banned(docs):
    hits = []
    for path in docs:
        lines = read(path)
        if lines is None:
            continue
        for i, line in enumerate(lines, 1):
            # Окно вокруг строки нужно дважды: случаям, растянутым на
            # несколько строк (`while true` и `live_tail` стоят в разных
            # строках няньки), и разбору грабли, где запрет написан строкой
            # ниже цитаты — абзац читается целиком, а не построчно.
            window = "\n".join(lines[max(0, i - 3):i + 3])
            if EXPLAINING.search(window):
                continue
            for pattern, needed, message in BANNED:
                if not pattern.search(line):
                    continue
                if needed and not needed.search(window):
                    continue
                hits.append(Hit(path, i, message))
                break
    return hits


def check_paths(docs):
    hits = []
    for path in docs:
        lines = read(path)
        if lines is None:
            continue
        for i, line in enumerate(lines, 1):
            for found in PATH_RE.findall(line):
                target = os.path.expanduser(found).rstrip(".,;:)`\"'")
                if "<" in target or "*" in target or "$" in target:
                    continue
                if not os.path.exists(target):
                    hits.append(Hit(path, i, f"путь не существует: {target}"))
    return hits


def _env_values(paths):
    """{имя: {значение: (файл, строка)}} по всем файлам."""
    found = {}
    for path in paths:
        lines = read(path)
        if lines is None:
            continue
        for i, line in enumerate(lines, 1):
            for name, value in ENV_RE.findall(line):
                value = value.strip("\"'\\")
                if PLACEHOLDER.match(value) or not value:
                    continue
                found.setdefault(name, {}).setdefault(value, (path, i))
    return found


def check_env(docs, skills):
    """Значение в доке разошлось со скиллом: скилл — источник правды."""
    doc_env = _env_values(docs)
    skill_env = _env_values(skills)
    hits = []
    for name, doc_values in doc_env.items():
        expected = skill_env.get(name)
        if not expected:
            continue
        for value, (path, line) in doc_values.items():
            if value not in expected:
                hits.append(Hit(path, line, (
                    f"{name}={value} расходится со скиллом "
                    f"({', '.join(sorted(expected))}) — источник правды скилл")))
    return hits


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--doc", action="append", default=None,
                    help="файл доки (можно несколько); по умолчанию — доки "
                         "живой транскрипции")
    ap.add_argument("--skill", action="append", default=None,
                    help="файл скилла для сверки env")
    a = ap.parse_args()

    docs = a.doc or DEFAULT_DOCS
    skills = a.skill if a.skill is not None else DEFAULT_SKILLS

    hits = check_banned(docs) + check_paths(docs) + check_env(docs, skills)
    hits.sort(key=lambda h: (h.path, h.line))
    for h in hits:
        print(f"{h.path}:{h.line}: {h.message}")
    print(f"\nрасхождений: {len(hits)}")
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main())
