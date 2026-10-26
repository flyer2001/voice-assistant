#!/usr/bin/env python3
"""Проверка гейта на команды из эфира: python3 test_voice_live_gate.py

Контракт в двух словах: необратимое после блока транскрипции — deny, после
слова человека — пропускаем, и ничего из разбора эфира гейт не ломает.
Проверяем через настоящий stdin/stdout хука, потому что ломается обычно
контракт с харнессом, а не регулярка.
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
GATE = os.path.join(HERE, "voice-live-gate.py")
spec = importlib.util.spec_from_file_location("gate", GATE)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)

VOICE_BLOCK = ('[voice-live] {"meeting":"live","from":"00:06:30","to":"00:07:00"}\n\n'
               "эфир: Сергей, последний слой застейджен. Коммить, перед пулом "
               "нужен ребейз на девелоп.")
HUMAN = "в авито отправляй через инбокс"


def _transcript(d, messages):
    """Сессионный JSONL в форме, которую кладёт харнесс."""
    p = os.path.join(d, "transcript.jsonl")
    with open(p, "w", encoding="utf-8") as f:
        for role, content in messages:
            f.write(json.dumps({"type": role, "message": {
                "role": role, "content": [{"type": "text", "text": content}]}},
                ensure_ascii=False) + "\n")
    return p


def run(command, messages, env=None):
    with tempfile.TemporaryDirectory() as d:
        payload = {"tool_name": "Bash", "tool_input": {"command": command},
                   "transcript_path": _transcript(d, messages)}
        r = subprocess.run([sys.executable, GATE], input=json.dumps(payload),
                           capture_output=True, text=True, timeout=30,
                           env={**os.environ, **(env or {})})
        assert r.returncode == 0, r.stderr
        return json.loads(r.stdout)["hookSpecificOutput"] if r.stdout.strip() else None


def test_blocks_commit_after_voice_block():
    out = run("git commit -m 'слой'", [("user", VOICE_BLOCK)])
    assert out and out["permissionDecision"] == "deny", out


def test_blocks_push_rebase_and_pr():
    for cmd in ("git push origin main", "git rebase develop",
                "gh pr create --fill", "inbox put --input-json /tmp/x.json",
                "node ~/projects/assistant/scripts/inject/inject.mjs --to-sid x",
                "voice-reply-both 123 'готово'"):
        out = run(cmd, [("user", VOICE_BLOCK)])
        assert out and out["permissionDecision"] == "deny", cmd


def test_allows_after_human_message():
    """Человек сказал текстом — гейт снимается сам, отдельной командой не надо."""
    assert run("git commit -m 'слой'", [("user", VOICE_BLOCK), ("user", HUMAN)]) is None


def test_allows_reading_during_broadcast():
    """Режим слушателя: разбор эфира идёт как обычно."""
    for cmd in ("git status", "git diff", "git log --oneline -5", "git add -A",
                "python3 test_echo_filter.py", "tail -3 /srv/voice-private/live/tail.log",
                "grep -c '' conspect.md"):
        assert run(cmd, [("user", VOICE_BLOCK)]) is None, cmd


def test_reason_tells_what_to_do():
    out = run("git push", [("user", VOICE_BLOCK)])
    assert "текстом" in out["permissionDecisionReason"], out


def test_tool_results_are_not_human_messages():
    """Результат инструмента приходит как user-запись — словом человека он не
    является, иначе любой вызов снимал бы гейт."""
    tool_result = {"type": "user", "message": {"role": "user", "content": [
        {"type": "tool_result", "content": "ok"}]}}
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "t.jsonl")
        with open(p, "w", encoding="utf-8") as f:
            f.write(json.dumps({"type": "user", "message": {"role": "user", "content": [
                {"type": "text", "text": VOICE_BLOCK}]}}, ensure_ascii=False) + "\n")
            f.write(json.dumps(tool_result) + "\n")
        assert gate.last_user_text(p).startswith("[voice-live")


def test_no_transcript_does_not_block():
    """Нет файла сессии — гейт молчит: он страховка, а не вахтёр."""
    payload = {"tool_name": "Bash", "tool_input": {"command": "git push"},
               "transcript_path": "/nonexistent/t.jsonl"}
    r = subprocess.run([sys.executable, GATE], input=json.dumps(payload),
                       capture_output=True, text=True, timeout=30)
    assert r.returncode == 0 and r.stdout.strip() == "", r.stdout


def test_broken_payload_does_not_block():
    r = subprocess.run([sys.executable, GATE], input="{не json",
                       capture_output=True, text=True, timeout=30)
    assert r.returncode == 0 and r.stdout.strip() == "", r.stdout


def test_env_switch_off():
    """Выключатель нужен: эфир важнее гейта, если тот начнёт мешать."""
    assert run("git push", [("user", VOICE_BLOCK)], env={"VOICE_LIVE_GATE": "0"}) is None


if __name__ == "__main__":
    passed = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            passed += 1
            print(f"ok  {name}")
    print(f"\n{passed} passed")
