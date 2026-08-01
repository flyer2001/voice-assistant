#!/usr/bin/env python3
"""Stop-hook core: найти в transcript ответ, адресованный voice-mac клиенту.

Linked reply = assistant-сообщения, чей parentUuid-путь ведёт к voice-mac
user-сообщению. Не "последний assistant" — тот может отвечать на другой,
более поздний turn в чате.

Логика вынесена из voice-mac-auto-reply.sh чтобы быть тестируемой:
`python3 test_voice_mac_auto_reply.py`.
"""
import json
import os
import re
import subprocess
import sys

MAX_TTS_CHARS = 2000
REPLY_CMD = "/usr/local/bin/voice-mac-reply-both"


def _parts(entry):
    msg = entry.get("message") or {}
    c = msg.get("content")
    if isinstance(c, list):
        return [p for p in c if isinstance(p, dict)]
    return []


def _joined_text(entry):
    msg = entry.get("message") or {}
    c = msg.get("content")
    if isinstance(c, str):
        return c
    parts = [p.get("text", "") for p in _parts(entry) if p.get("type") == "text"]
    return "\n".join(parts) if parts else None


def user_text(entry):
    return _joined_text(entry) if entry.get("type") == "user" else None


def assistant_text(entry):
    if entry.get("type") != "assistant":
        return None
    t = _joined_text(entry)
    return t.strip() if t else None


def is_tool_result(entry):
    """user-запись, несущая результат инструмента, а не реплику человека.

    В transcript таких записей кратно больше настоящих реплик (73 vs 15 на
    типичной сессии). Раньше обход обрывался на первой из них, поэтому в TTS
    уходил только текст до первого вызова инструмента — обычно пустой.
    """
    if entry.get("type") != "user":
        return False
    if entry.get("toolUseResult") is not None:
        return True
    return any(p.get("type") == "tool_result" for p in _parts(entry))


def starts_new_turn(entry):
    """Настоящая реплика человека — дальше её ответы уже не наши."""
    return entry.get("type") == "user" and not is_tool_result(entry)


def find_voice_user(entries):
    for e in reversed(entries):
        t = user_text(e)
        if t and t.lstrip().startswith("[voice-mac") and not is_tool_result(e):
            return e
    return None


def client_id(entry):
    m = re.search(r"client_id=([A-Za-z0-9_-]+)", user_text(entry) or "")
    return m.group(1) if m else "mac-home"


def collect_reply(entries):
    """(client_id, combined_text) или (None, None) если отвечать нечего."""
    voice_user = find_voice_user(entries)
    if not voice_user or not voice_user.get("uuid"):
        return None, None

    children = {}
    for e in entries:
        p = e.get("parentUuid")
        # ponytail: sidechain = subagent-ветка, её текст не для пользователя.
        if p and not e.get("isSidechain"):
            children.setdefault(p, []).append(e)

    texts = []
    cur = voice_user["uuid"]
    seen = set()
    while cur is not None and cur not in seen:
        seen.add(cur)
        kids = children.get(cur) or []
        if not kids:
            break
        kids.sort(key=lambda e: e.get("timestamp") or "")
        child = kids[0]
        if starts_new_turn(child):
            break
        t = assistant_text(child)
        if t:
            texts.append(t)
        cur = child.get("uuid")

    if not texts:
        return None, None
    combined = "\n\n".join(texts)[:MAX_TTS_CHARS].strip()
    return (client_id(voice_user), combined) if combined else (None, None)


def read_entries(path):
    out = []
    with open(path) as fh:
        for line in fh:
            try:
                out.append(json.loads(line))
            except Exception:
                continue
    return out


def main(path):
    cid, combined = collect_reply(read_entries(path))
    if not combined:
        return 0

    marker = f"/tmp/voice-mac-hook-last-{cid}.txt"
    if os.path.exists(marker):
        try:
            if open(marker).read() == combined:
                return 0
        except Exception:
            pass
    open(marker, "w").write(combined)

    subprocess.Popen(
        [REPLY_CMD, cid, combined],
        stdout=open("/tmp/voice-mac-auto-reply.log", "a"),
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
