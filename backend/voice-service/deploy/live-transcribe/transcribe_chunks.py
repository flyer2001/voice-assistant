#!/usr/bin/env python3
"""Смотрит за каталогом с чанками и дописывает расшифровку в живой файл.

Чанки нарезает ffmpeg (см. capture.sh), сюда они приезжают готовыми. Файл
растёт построчно, его можно читать по ходу:

    ssh mac-home 'tail -c 3000 ~/podlodka/live.md'

Распознаёт локально через mlx-whisper, либо шлёт на CUDA-эндпоинт, если
задан VOICE_WHISPER_URL. Модель держится в памяти между чанками — загрузка
2.8 с только на старте.

    ./transcribe_chunks.py ~/podlodka/chunks ~/podlodka/live.md
    VOICE_WHISPER_URL=http://192.168.88.13:8000 ./transcribe_chunks.py ...
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.request

MODEL = os.environ.get("VOICE_WHISPER_MODEL", "mlx-community/whisper-large-v3-mlx")
REMOTE = os.environ.get("VOICE_WHISPER_URL", "").rstrip("/")
LANG = os.environ.get("VOICE_LANG", "ru")
PROMPT = os.environ.get("VOICE_INITIAL_PROMPT", "")
POLL_S = float(os.environ.get("VOICE_POLL_S", "1"))

# ffmpeg -f segment нумерует файлы подряд: chunk-000.wav, chunk-001.wav...
CHUNK_RE = re.compile(r"^chunk-(\d+)\.(wav|mp3|m4a)$")

_local_model_loaded = False


def log(msg):
    print(f"{time.strftime('%H:%M:%S')} {msg}", file=sys.stderr, flush=True)


def transcribe_remote(path):
    """CUDA-эндпоинт. curl, а не requests — лишних пакетов на маке нет."""
    cmd = ["curl", "-s", "--max-time", "300",
           "-F", f"audio=@{path}", "-F", f"lang_hint={LANG}"]
    if PROMPT:
        cmd += ["-F", f"initial_prompt={PROMPT}"]
    cmd.append(f"{REMOTE}/transcribe")
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"curl exit {r.returncode}: {r.stderr[:200]}")
    return json.loads(r.stdout).get("text", "").strip()


def transcribe_local(path):
    global _local_model_loaded
    import mlx_whisper
    kw = {"path_or_hf_repo": MODEL, "language": LANG}
    if PROMPT:
        kw["initial_prompt"] = PROMPT
    if not _local_model_loaded:
        log(f"загружаю модель {MODEL} (несколько секунд, один раз)")
        _local_model_loaded = True
    return (mlx_whisper.transcribe(path, **kw).get("text") or "").strip()


def transcribe(path):
    return transcribe_remote(path) if REMOTE else transcribe_local(path)


def stamp(index, chunk_seconds):
    """Таймкод от начала записи — по номеру чанка, а не по часам.

    Нужен именно относительный: в записи доклада «на 14-й минуте» полезнее,
    чем «в 15:42», особенно когда потом перечитываешь.
    """
    total = index * chunk_seconds
    return f"{total // 3600:02d}:{(total % 3600) // 60:02d}:{total % 60:02d}"


def ready_chunks(chunks_dir):
    """Готовые чанки по возрастанию номера.

    Последний по номеру пропускаем: ffmpeg в него пишет прямо сейчас, и
    распознавать его рано — получим обрывок.
    """
    found = []
    for name in os.listdir(chunks_dir):
        m = CHUNK_RE.match(name)
        if m:
            found.append((int(m.group(1)), name))
    found.sort()
    return found[:-1] if found else []


def append(out_path, text):
    with open(out_path, "a") as fh:
        fh.write(text)
        fh.flush()
        os.fsync(fh.fileno())


def write_header(out_path, args):
    if os.path.exists(out_path) and os.path.getsize(out_path) > 0:
        return
    started = time.strftime("%Y-%m-%d %H:%M:%S")
    head = [f"# {args.title or 'Расшифровка'}", "", f"Начато: {started}"]
    if args.consent:
        head.append("Участники предупреждены о записи: да")
    head += ["", "---", ""]
    append(out_path, "\n".join(head) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("chunks_dir")
    ap.add_argument("out_file")
    ap.add_argument("--chunk-seconds", type=int, default=30)
    ap.add_argument("--title", default="")
    ap.add_argument("--consent", action="store_true",
                    help="участники предупреждены о записи (созвон, собеседование)")
    ap.add_argument("--require-consent", action="store_true",
                    help="не стартовать без --consent; ставится вызывающим "
                         "для режимов, где в записи чужие голоса")
    args = ap.parse_args()

    if args.require_consent and not args.consent:
        sys.exit("отказ: режим требует подтверждения, что участники предупреждены "
                 "о записи. Добавь --consent, если это так.")

    os.makedirs(args.chunks_dir, exist_ok=True)
    os.makedirs(os.path.dirname(os.path.abspath(args.out_file)) or ".", exist_ok=True)
    write_header(args.out_file, args)

    log(f"слежу за {args.chunks_dir}, пишу в {args.out_file}")
    log(f"движок: {'CUDA ' + REMOTE if REMOTE else 'локальный mlx'}")

    done = set()
    while True:
        try:
            for index, name in ready_chunks(args.chunks_dir):
                if index in done:
                    continue
                path = os.path.join(args.chunks_dir, name)
                t0 = time.time()
                text = transcribe(path)
                took = time.time() - t0
                done.add(index)
                if not text:
                    log(f"чанк {index}: тишина ({took:.1f}с)")
                    continue
                append(args.out_file, f"**[{stamp(index, args.chunk_seconds)}]** {text}\n\n")
                log(f"чанк {index}: {took:.1f}с, {len(text)} символов")
        except Exception as e:
            # Файл ещё дописывается, сеть моргнула, эндпоинт перезапускается —
            # не роняем запись доклада из-за одного чанка.
            log(f"ошибка: {e}")
        time.sleep(POLL_S)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log("остановлено")
