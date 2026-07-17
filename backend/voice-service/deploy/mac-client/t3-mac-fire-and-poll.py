#!/usr/bin/env python3
"""T3: mic/text -> whisper -> POST intent (fire-and-forget) -> poll /voice-out/ for reply.

Usage:
  t3-mac-fire-and-poll.py                 # record 5s from mic
  t3-mac-fire-and-poll.py --text "..."    # skip mic, use given transcript
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
import wave
from datetime import datetime, timezone
from pathlib import Path

# --- 0. Aqua re-exec ---------------------------------------------------------
# CoreAudio input is unreachable from the Background launchd domain (an SSH/tmux
# session): sd.rec() yields peak=0 and no TCC prompt can ever appear. Re-exec via
# `launchctl asuser` to land in the GUI session's Aqua domain. No root needed —
# target uid == our uid, so it is not a privilege escalation.
_GUARD = "T3_AQUA_REEXEC"


def _managername():
    try:
        r = subprocess.run(["launchctl", "managername"],
                           capture_output=True, text=True, timeout=5)
        return r.stdout.strip() if r.returncode == 0 else f"?(exit={r.returncode})"
    except Exception as exc:
        return f"?({type(exc).__name__})"


_mgr = _managername()
print(f"=== launchd domain: {_mgr} ===", flush=True)
if _mgr != "Aqua":
    if os.environ.get(_GUARD):
        # asuser ran but we are still not in Aqua — bail rather than fork-bomb.
        print(f"FAIL: still {_mgr} after asuser re-exec — giving up", flush=True)
        sys.exit(11)
    os.environ[_GUARD] = "1"
    print(f"=== re-exec via launchctl asuser {os.getuid()} -> Aqua ===", flush=True)
    os.execvp("launchctl", ["launchctl", "asuser", str(os.getuid()),
                            sys.executable, os.path.abspath(__file__), *sys.argv[1:]])
    # execvp does not return; if it raises, the traceback is the report.

RATE = 16000
SECONDS = 5
WAV = "/tmp/t3-rec.wav"
TXT = "/tmp/t3-rec.txt"
CLI = "/Users/flyer2001/projects/voice-assistant/clients/voice-agent-mac/.venv/bin/mlx_whisper"
# NB: bare "mlx-community/whisper-large-v3" does not exist — HF answers 401 for it.
MODEL = "mlx-community/whisper-large-v3-mlx"
# Biases decoding toward domain jargon Whisper would otherwise russify into noise.
INITIAL_PROMPT = ("Обсуждаем voice-agent, whisper, tmux, macOS, iTerm, VDS, subagent, "
                  "Caddy, TTS, Yandex, Anthropic, Claude, LLM, mac-home, git, SSH")
CFG = Path.home() / ".voice-agent-mac" / "config.json"
CLIENT_ID = "mac-home"
POLL_EVERY = 2
POLL_MAX = 90
PLACEHOLDER = "..."


def die(msg, code=1):
    print(f"FAIL: {msg}", flush=True)
    sys.exit(code)


def now_ts():
    """ISO-basic UTC ms, e.g. 20260717T075350582Z — lexicographically sortable."""
    t = datetime.now(timezone.utc)
    return t.strftime("%Y%m%dT%H%M%S") + f"{t.microsecond // 1000:03d}Z"


def play(path):
    """afplay (CoreAudio) has no Ogg/Opus codec — transcode via ffmpeg on failure.
    Blocking: we want playback_ms, and exiting mid-stream would cut the audio off."""
    r = subprocess.run(["afplay", path], capture_output=True, text=True)
    if r.returncode == 0:
        return "afplay", None
    wav = str(Path(path).with_suffix(".conv.wav"))
    c = subprocess.run(["ffmpeg", "-y", "-i", path, wav],
                       capture_output=True, text=True)
    if c.returncode != 0:
        return None, f"afplay: {r.stderr.strip()[:200]} | ffmpeg: {c.stderr.strip()[-200:]}"
    r2 = subprocess.run(["afplay", wav], capture_output=True, text=True)
    if r2.returncode != 0:
        return None, f"afplay(wav): {r2.stderr.strip()[:200]}"
    return "ffmpeg->afplay", None


ap = argparse.ArgumentParser()
ap.add_argument("--text", help="skip mic, use this transcript verbatim")
args = ap.parse_args()

# --- config ---
if not CFG.exists():
    die(f"config missing: {CFG}")
try:
    _cfg = json.loads(CFG.read_text())
except Exception as exc:
    die(f"config unreadable {CFG}: {type(exc).__name__}: {exc}")
be = _cfg.get("voice_backend") or {}
# ponytail: config override; keeps hardcoded prompt as fallback
INITIAL_PROMPT = (_cfg.get("whisper") or {}).get("initial_prompt") or INITIAL_PROMPT
url_base = (be.get("url") or "").rstrip("/")
token = be.get("token")
if not url_base:
    die(f"config missing voice_backend.url in {CFG}")
if not token or token == PLACEHOLDER:
    die(f"config has placeholder/empty voice_backend.token in {CFG}")
print(f"=== config OK: url={url_base} token_len={len(token)} client_id={CLIENT_ID} ===", flush=True)

# --- 1. transcript: mic or override ---
if args.text:
    transcript = args.text.strip()
    print(f"=== --text override, mic SKIPPED ===", flush=True)
else:
    import sounddevice as sd
    print(f"=== recording {SECONDS}s @ {RATE}Hz mono int16 — SPEAK NOW ===", flush=True)
    try:
        frames = sd.rec(int(SECONDS * RATE), samplerate=RATE, channels=1, dtype="int16")
        sd.wait()
    except Exception as exc:
        die(f"record: {type(exc).__name__}: {exc}", 4)
    with wave.open(WAV, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames.tobytes())
    peak = int(abs(frames).max())
    print(f"=== wrote {WAV} peak_amplitude={peak}/32767 ===", flush=True)
    if peak == 0:
        die("pure silence (peak=0) — mic not reaching process; use --text to test the poll path", 4)

    # mlx_whisper exits 0 even when it fails (it prints "Skipping <file> due to ..."
    # and moves on), so returncode alone cannot be trusted. Delete the previous
    # output first: without this a failed run silently reuses the stale transcript.
    Path(TXT).unlink(missing_ok=True)

    print(f"=== transcribing via {MODEL} ===", flush=True)
    _t_stt = time.monotonic()
    res = subprocess.run(
        [CLI, WAV, "--model", MODEL,
         "--language", "ru", "--initial-prompt", INITIAL_PROMPT,
         "--output-dir", "/tmp"],
        capture_output=True, text=True,
    )
    stt_ms = int((time.monotonic() - _t_stt) * 1000)
    if res.returncode != 0:
        print(res.stderr[-2000:], flush=True)
        die(f"mlx_whisper exit={res.returncode}", 5)
    if not Path(TXT).exists():
        print((res.stderr or res.stdout)[-2000:], flush=True)
        die(f"mlx_whisper exit=0 but produced no {TXT} — transcription failed silently", 5)
    print(f"STT        | {stt_ms}ms (incl. model load/download if uncached)", flush=True)
    transcript = Path(TXT).read_text().strip()

if not transcript:
    die("empty transcript — nothing to POST", 6)
print(f"TRANSCRIPT | {transcript}", flush=True)

# marker triggers the VDS Stop hook, which auto-invokes voice-mac-reply-both
posted_text = f"[voice-mac client_id={CLIENT_ID}]\n{transcript}"
print(f"POSTING    | {posted_text!r}", flush=True)

# mark the cutoff BEFORE the POST so a fast reply can't land before our watermark
start_ts = now_ts()
print(f"=== watermark {start_ts} ===", flush=True)

# --- 2. POST intent, fire-and-forget ---
endpoint = f"{url_base}/v1/voice/intent"
payload = json.dumps({
    "text": posted_text,
    "client_id": CLIENT_ID,
    "ts": datetime.now(timezone.utc).isoformat(),
}).encode()
req = urllib.request.Request(
    endpoint, data=payload, method="POST",
    headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
)
print(f"=== POST {endpoint} ===", flush=True)
try:
    with urllib.request.urlopen(req, timeout=10) as r:
        print(f"=== POST {r.status} — inject fired (sync reply ignored) ===", flush=True)
except urllib.error.HTTPError as exc:
    body = exc.read()[:200].decode(errors="replace")
    if exc.code >= 500:
        print(f"=== POST {exc.code} ({body}) — treating as fired per contract ===", flush=True)
    else:
        # 401/403/404 mean the request was rejected outright: inject did NOT fire.
        die(f"POST {exc.code} — request rejected, inject did not fire: {body}", 7)
except Exception as exc:
    print(f"=== POST {type(exc).__name__}: {exc} — treating as fired (timeout) ===", flush=True)

# --- 3-6. poll for reply ---
listing_url = f"{url_base}/voice-out/"
name_re = re.compile(rf"^{re.escape(CLIENT_ID)}-(\d{{8}}T\d{{9}}Z)\.json$")
href_re = re.compile(r'href="\.?/?([^"?]+\.json)"', re.I)

print(f"waiting for reply... (poll {listing_url} every {POLL_EVERY}s, max {POLL_MAX}s)", flush=True)
t0 = time.monotonic()
attempt = 0
while True:
    waited = time.monotonic() - t0
    if waited > POLL_MAX:
        die(f"no reply after {POLL_MAX}s (watermark {start_ts}, client_id {CLIENT_ID})", 3)
    attempt += 1
    names = []
    try:
        lreq = urllib.request.Request(listing_url, headers={"Accept": "application/json"})
        with urllib.request.urlopen(lreq, timeout=10) as r:
            body = r.read().decode(errors="replace")
        try:
            # Caddy file_server browse returns JSON when Accept: application/json
            data = json.loads(body)
            names = [e.get("name", "") for e in data] if isinstance(data, list) else []
        except json.JSONDecodeError:
            names = href_re.findall(body)  # fallback: HTML listing
    except Exception as exc:
        print(f"  [{waited:5.1f}s] listing error: {type(exc).__name__}: {exc}", flush=True)
        time.sleep(POLL_EVERY)
        continue

    # exact client_id + ts-shaped suffix — avoids matching e.g. mac-home-t2-*.json
    fresh = []
    for n in names:
        m = name_re.match(n.strip().split("/")[-1])
        if m and m.group(1) > start_ts:
            fresh.append((m.group(1), n))
    if fresh:
        ts, name = max(fresh)  # race: take latest by ts
        if len(fresh) > 1:
            print(f"  note: {len(fresh)} new replies, taking latest {ts}", flush=True)
        try:
            with urllib.request.urlopen(f"{listing_url}{name}", timeout=10) as r:
                doc = json.loads(r.read().decode())
        except Exception as exc:
            die(f"fetch {name}: {type(exc).__name__}: {exc}", 8)
        waited = time.monotonic() - t0
        print("", flush=True)
        print(f"TRANSCRIPT | {transcript}", flush=True)
        print(f"REPLY      | {doc.get('text')}", flush=True)
        print(f"WAIT_TIME  | {waited:.1f}s ({attempt} polls) file={name}", flush=True)

        audio_url = doc.get("audio_url")
        if not audio_url:
            print("AUDIO      | none (text-only reply)", flush=True)
            sys.exit(0)

        print(f"AUDIO      | {audio_url} voice={doc.get('voice')} "
              f"size={doc.get('audio_size')}", flush=True)
        local = "/tmp/" + Path(audio_url).name
        t1 = time.monotonic()
        try:
            with urllib.request.urlopen(url_base + audio_url, timeout=30) as r:
                blob = r.read()
        except Exception as exc:
            die(f"audio download {audio_url}: {type(exc).__name__}: {exc}", 9)
        Path(local).write_bytes(blob)
        dl_ms = int((time.monotonic() - t1) * 1000)
        print(f"DOWNLOAD   | {dl_ms}ms {len(blob)}B -> {local}", flush=True)
        if doc.get("audio_size") is not None and len(blob) != doc["audio_size"]:
            print(f"  warn: audio_size={doc['audio_size']} but got {len(blob)}B", flush=True)

        t2 = time.monotonic()
        how, err = play(local)
        play_ms = int((time.monotonic() - t2) * 1000)
        if err:
            print(f"PLAYBACK   | FAILED after {play_ms}ms — {err}", flush=True)
            sys.exit(10)
        print(f"PLAYBACK   | {play_ms}ms via {how}", flush=True)
        sys.exit(0)

    if attempt % 5 == 1:
        print(f"  [{waited:5.1f}s] {len(names)} files listed, none newer than watermark", flush=True)
    time.sleep(POLL_EVERY)
