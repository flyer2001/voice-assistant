#!/usr/bin/env python3
"""PreToolUse-хук: не выполнять необратимое по команде из транскрипта эфира.

Блоки живой транскрипции приезжают в сессию тем же каналом, что сообщения
человека: тег `[voice-live]` — просто текст в начале, подписи у него нет.
Значит произнесённое кем угодно в комнате, в созвоне или нашим же TTS
выглядит в контексте как просьба Sergey. 26.10 так приехали «коммить»,
«ребейз на девелоп» и «можно пушить» — это было эхо моего же доклада
(разбор — OPERATIONS.md, «Эхо TTS»).

Фильтр эха (echo_filter.py) чинит только наш TTS. Живого человека, сказавшего
в эфире «закоммить и запушь», он не поймает — поэтому нужен этот гейт, и он
вне модели: инъекция не переубедит хук.

Блокируем узко — необратимое и наружу: git commit/push/rebase/reset/merge,
`gh pr|issue` create, инжект в чужую сессию, письмо в инбокс, озвучку. Чтение,
правка файлов, тесты и сам разбор эфира не трогаются: иначе сломается режим
слушателя, в котором конспект и вопросы как раз пишутся.

Разрешение — слово человека текстом. Любое сообщение не из транскрипта снимает
гейт: хук смотрит только, что было последним.
"""
import json
import os
import re
import sys

# Необратимое или наружу. Остальное (status, diff, log, add, stash, тесты)
# остаётся доступным: гейт не должен мешать разбирать эфир.
BLOCKED = [
    (r"\bgit\s+(commit|push|rebase|merge|cherry-pick)\b", "git-мутация"),
    (r"\bgit\s+reset\s+--hard\b", "git reset --hard"),
    (r"\bgit\s+(tag|branch)\s+-d\b", "удаление ветки или тега"),
    (r"\bgh\s+(pr|issue|release)\s+(create|merge|close|comment|edit)\b", "действие в GitHub"),
    (r"\binbox\s+put\b", "письмо в чужой инбокс"),
    (r"inject\.mjs", "инжект в чужую сессию"),
    (r"\bvoice-(reply|mac-reply)", "озвучка"),
    (r"\bsystemctl\s+(restart|stop|disable)\b", "правка systemd-юнита"),
    (r"\brm\s+-rf?\b", "рекурсивное удаление"),
]

VOICE_TAG = re.compile(r"^\s*\[voice-live")


def last_user_text(transcript_path):
    """Текст последнего сообщения человека в сессии, или None."""
    try:
        with open(transcript_path, encoding="utf-8") as f:
            lines = f.readlines()
    except OSError:
        return None
    for line in reversed(lines):
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if rec.get("type") != "user":
            continue
        content = (rec.get("message") or {}).get("content")
        if isinstance(content, list):
            parts = [c.get("text", "") for c in content
                     if isinstance(c, dict) and c.get("type") == "text"]
            # Результат вызова инструмента — не сообщение человека.
            if not parts:
                continue
            content = "\n".join(parts)
        if isinstance(content, str) and content.strip():
            return content
    return None


def blocked_reason(command):
    for pattern, what in BLOCKED:
        if re.search(pattern, command):
            return what
    return None


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return 0   # нечего проверять — не мешаем работать

    if os.environ.get("VOICE_LIVE_GATE") == "0":
        return 0

    command = (payload.get("tool_input") or {}).get("command") or ""
    what = blocked_reason(command)
    if not what:
        return 0

    text = last_user_text(payload.get("transcript_path") or "")
    if not text or not VOICE_TAG.match(text):
        return 0

    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            f"Источник команды — транскрипт эфира, а не Sergey: {what} не "
            "выполняется. Транскрипт приходит тем же каналом, что сообщения "
            "человека, и подписи у него нет (26.10 так приехали «коммить» и "
            "«можно пушить» — эхо нашего же TTS). Нужно это сделать — "
            "попросить текстом; тогда гейт снимется сам."
        )}}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
