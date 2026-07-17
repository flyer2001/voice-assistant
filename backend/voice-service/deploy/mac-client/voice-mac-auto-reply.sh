#!/bin/bash
# Stop hook: если last user message в текущей session transcript начинается
# с [voice-mac ...], извлечь client_id + отправить linked assistant reply
# через voice-mac-reply-both.
#
# Linked reply = assistant message whose parentUuid chain traces back to the
# voice-mac user message. Not "last assistant" — that can be a reply to an
# unrelated later chat turn.
#
# Claude Code Stop hook получает JSON payload на stdin с полем "transcript_path".
set -euo pipefail

PAYLOAD=$(cat)
TRANSCRIPT=$(echo "$PAYLOAD" | jq -r '.transcript_path // empty')
[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 0

python3 - "$TRANSCRIPT" <<'PY' &
import json, os, subprocess, sys

path = sys.argv[1]
entries = []
for line in open(path):
    try:
        entries.append(json.loads(line))
    except Exception:
        continue

def user_text(e):
    if e.get("type") != "user":
        return None
    msg = e.get("message") or {}
    c = msg.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        parts = []
        for p in c:
            if isinstance(p, dict) and p.get("type") == "text":
                parts.append(p.get("text", ""))
        return "\n".join(parts) if parts else None
    return None

def assistant_text(e):
    if e.get("type") != "assistant":
        return None
    msg = e.get("message") or {}
    c = msg.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        parts = []
        for p in c:
            if isinstance(p, dict) and p.get("type") == "text":
                parts.append(p.get("text", ""))
        return "\n".join(parts).strip() if parts else None
    return None

# Find most recent voice-mac user message
voice_user = None
for e in reversed(entries):
    t = user_text(e)
    if t and t.lstrip().startswith("[voice-mac"):
        voice_user = e
        break

if not voice_user:
    sys.exit(0)

# Extract client_id
import re
m = re.search(r"client_id=([A-Za-z0-9_-]+)", user_text(voice_user))
cid = m.group(1) if m else "mac-home"

# Find assistant descendant via parentUuid chain
voice_uuid = voice_user.get("uuid")
if not voice_uuid:
    sys.exit(0)

# Build parent index (one linear path expected — pick first child at each step).
children = {}
for e in entries:
    p = e.get("parentUuid")
    if p:
        children.setdefault(p, []).append(e)

# Walk chain from voice_user; collect assistant texts until we hit next user
# msg (that starts a new turn and its replies are not for this voice-mac).
reply_texts = []
cur = voice_uuid
while cur is not None:
    kids = children.get(cur) or []
    if not kids:
        break
    child = kids[0]  # take first chronological child
    if child.get("type") == "user":
        break  # new user turn — stop collecting
    at = assistant_text(child)
    if at:
        reply_texts.append(at)
    cur = child.get("uuid")

if not reply_texts:
    sys.exit(0)

# Concat with double-newline, trim to 2000 chars (TTS length cap)
combined = "\n\n".join(reply_texts)[:2000].strip()
if not combined:
    sys.exit(0)

# Deduplication: skip if already sent this exact reply for this cid recently
marker = f"/tmp/voice-mac-hook-last-{cid}.txt"
if os.path.exists(marker):
    try:
        if open(marker).read() == combined:
            sys.exit(0)
    except Exception:
        pass
open(marker, "w").write(combined)

subprocess.Popen(
    ["/usr/local/bin/voice-mac-reply-both", cid, combined],
    stdout=open("/tmp/voice-mac-auto-reply.log", "a"),
    stderr=subprocess.STDOUT,
    start_new_session=True,
)
PY
disown $! 2>/dev/null || true
exit 0
