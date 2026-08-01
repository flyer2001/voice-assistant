#!/usr/bin/env python3
"""Проверка обхода parentUuid-цепочки. Запуск: python3 test_voice_mac_auto_reply.py

Без фреймворка — hook работает на mac-home, где pytest ставить незачем.
"""
from voice_mac_auto_reply import collect_reply

_ts = [0]


def _next_ts():
    _ts[0] += 1
    return f"2026-08-01T10:00:{_ts[0]:02d}Z"


def user(uuid, parent, text):
    return {"type": "user", "uuid": uuid, "parentUuid": parent,
            "timestamp": _next_ts(), "promptSource": "cli",
            "message": {"content": text}}


def tool_result(uuid, parent):
    return {"type": "user", "uuid": uuid, "parentUuid": parent,
            "timestamp": _next_ts(), "toolUseResult": {"stdout": "ok"},
            "message": {"content": [{"type": "tool_result", "content": "ok"}]}}


def assistant(uuid, parent, text=None, tool=False, sidechain=False):
    content = []
    if text:
        content.append({"type": "text", "text": text})
    if tool:
        content.append({"type": "tool_use", "name": "Bash", "input": {}})
    return {"type": "assistant", "uuid": uuid, "parentUuid": parent,
            "timestamp": _next_ts(), "isSidechain": sidechain,
            "message": {"content": content}}


VOICE = "[voice-mac client_id=mac-home]\nкакая погода"


def test_plain_reply():
    es = [user("u1", None, VOICE), assistant("a1", "u1", "Ответ.")]
    assert collect_reply(es) == ("mac-home", "Ответ.")


def test_reply_survives_tool_calls():
    """Регрессия: обход обрывался на первом tool_result → терялся финальный текст."""
    es = [
        user("u1", None, VOICE),
        assistant("a1", "u1", tool=True),          # вызов без текста
        tool_result("t1", "a1"),
        assistant("a2", "t1", "Сейчас +18."),      # настоящий ответ
    ]
    assert collect_reply(es) == ("mac-home", "Сейчас +18.")


def test_stops_at_next_human_turn():
    """Реплика Sergey'я начинает новый turn — её ответ не для voice-mac."""
    es = [
        user("u1", None, VOICE),
        assistant("a1", "u1", "Ответ на голос."),
        user("u2", "a1", "а теперь про другое"),
        assistant("a2", "u2", "Ответ на текст."),
    ]
    cid, text = collect_reply(es)
    assert text == "Ответ на голос.", text
    assert "текст" not in text


def test_ignores_sidechain():
    """Текст субагента не должен уезжать в TTS."""
    es = [
        user("u1", None, VOICE),
        assistant("sc", "u1", "Внутренние рассуждения субагента.", sidechain=True),
        assistant("a1", "u1", "Готово."),
    ]
    assert collect_reply(es) == ("mac-home", "Готово.")


def test_no_voice_message():
    es = [user("u1", None, "обычный текст"), assistant("a1", "u1", "ок")]
    assert collect_reply(es) == (None, None)


def test_tts_cap():
    es = [user("u1", None, VOICE), assistant("a1", "u1", "я" * 5000)]
    _, text = collect_reply(es)
    assert len(text) == 2000


def test_cycle_does_not_hang():
    """Битый transcript с петлёй parentUuid не должен вешать hook."""
    es = [
        user("u1", None, VOICE),
        assistant("a1", "u1", "раз"),
        assistant("a2", "a1", "два"),
        {"type": "assistant", "uuid": "a1", "parentUuid": "a2",
         "timestamp": "2026-08-01T10:00:99Z", "message": {"content": []}},
    ]
    cid, text = collect_reply(es)
    assert text == "раз\n\nдва", text


if __name__ == "__main__":
    passed = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            _ts[0] = 0
            fn()
            passed += 1
            print(f"ok  {name}")
    print(f"\n{passed} passed")
