#!/usr/bin/env python3
"""Прикрепляет скриншоты к транскрипту по времени.

Sergey во время доклада жмёт штатный ⌘⇧4 — снимки падают на Desktop с
временем в имени или в mtime. После расшифровки этот скрипт вставляет
каждый снимок под ближайший таймкод транскрипта.

    ./attach_screenshots.py transcript.md shots_dir --start "2026-09-14 11:00:05"

--start — момент начала записи по стенным часам. OBS пишет его в имя файла
записи ("2026-09-14 11-00-05.mkv"), можно скопировать оттуда.
"""
import argparse
import os
import re
import shutil
import sys
from datetime import datetime, timedelta

TIMECODE = re.compile(r'^\*\*\[(\d{2}):(\d{2}):(\d{2})\]\*\*')


def shot_time(path):
    """Когда снят скриншот. Имя надёжнее mtime: файл могли скопировать."""
    name = os.path.basename(path)
    m = re.search(r'Screenshot_(\d{10})', name)          # unix ts в имени
    if m:
        return datetime.fromtimestamp(int(m.group(1)))
    m = re.search(r'(\d{4}-\d{2}-\d{2}) at (\d{1,2})\.(\d{2})\.(\d{2})', name)
    if m:                                                 # "Screenshot 2026-09-14 at 11.23.45"
        return datetime.strptime(
            f"{m.group(1)} {m.group(2)}:{m.group(3)}:{m.group(4)}",
            "%Y-%m-%d %H:%M:%S")
    m = re.search(r'(\d{4}-\d{2}-\d{2}) (\d{2})-(\d{2})-(\d{2})', name)
    if m:                                                 # OBS: "Screenshot 2026-09-14 11-23-45.png"
        return datetime.strptime(
            f"{m.group(1)} {m.group(2)}:{m.group(3)}:{m.group(4)}",
            "%Y-%m-%d %H:%M:%S")
    return datetime.fromtimestamp(os.path.getmtime(path))


def parse_transcript(path):
    """[(offset_seconds, line_index)] по таймкодам + все строки."""
    lines = open(path).read().splitlines()
    marks = []
    for i, line in enumerate(lines):
        m = TIMECODE.match(line)
        if m:
            h, mn, s = map(int, m.groups())
            marks.append((h * 3600 + mn * 60 + s, i))
    return lines, marks


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("transcript")
    ap.add_argument("shots_dir")
    ap.add_argument("--start", required=True,
                    help='начало записи, "YYYY-MM-DD HH:MM:SS"')
    ap.add_argument("--out", default=None, help="куда писать (default: in place)")
    args = ap.parse_args()

    # Журнал обработанных — в папке снимков, простой текст. Строка есть —
    # снимок обработан и повторно не клеится (можно гонять скрипт сколько
    # угодно). Sergey регулирует руками: удалил строку — снимок обработается
    # заново, вписал сам — будет пропущен.
    ledger_path = os.path.join(args.shots_dir, "processed.md")
    done = set()
    if os.path.exists(ledger_path):
        for line in open(ledger_path):
            name = line.split("→")[0].strip("- ").strip()
            if name:
                done.add(name)

    start = datetime.strptime(args.start, "%Y-%m-%d %H:%M:%S")
    lines, marks = parse_transcript(args.transcript)
    if not marks:
        sys.exit("в транскрипте нет таймкодов вида **[HH:MM:SS]**")
    # Верхняя граница: конец записи ≈ последний таймкод + чанк. Снимок,
    # сделанный на СЛЕДУЮЩЕМ докладе, иначе приклеился бы в хвост этого —
    # поймано 2026-09-14, снимок Мирзояна попал в конспект Бугра.
    last_offset = marks[-1][0] + 60

    # Копируем снимки в assets/ рядом с транскриптом — Desktop у Sergey
    # чистится, а конспект должен остаться самодостаточным.
    base_dir = os.path.dirname(os.path.abspath(args.transcript))
    assets = os.path.join(base_dir, "assets")

    shots = []
    for name in sorted(os.listdir(args.shots_dir)):
        if not name.lower().endswith((".png", ".jpg", ".jpeg")):
            continue
        if name in done:
            continue                       # уже обработан по журналу
        p = os.path.join(args.shots_dir, name)
        offset = (shot_time(p) - start).total_seconds()
        if offset < 0 or offset > last_offset:
            continue                       # снят до начала или после конца
        shots.append((offset, p))

    if not shots:
        sys.exit("подходящих скриншотов не нашлось (все обработаны или вне записи)")

    os.makedirs(assets, exist_ok=True)
    # К каждому снимку — последний таймкод, что был на экране в этот момент.
    inserts = {}                           # line_index -> [markdown]
    for offset, p in shots:
        prior = [(off, li) for off, li in marks if off <= offset]
        _, line_idx = prior[-1] if prior else marks[0]
        dst = os.path.join(assets, os.path.basename(p))
        shutil.copy2(p, dst)
        stamp = str(timedelta(seconds=int(offset)))
        rel = os.path.join("assets", os.path.basename(p))
        inserts.setdefault(line_idx, []).append(
            f"\n![скриншот на {stamp}]({rel})\n")

    out_lines = []
    for i, line in enumerate(lines):
        out_lines.append(line)
        for md in inserts.get(i, []):
            out_lines.append(md)

    out_path = args.out or args.transcript
    with open(out_path, "w") as fh:
        fh.write("\n".join(out_lines) + "\n")

    with open(ledger_path, "a") as fh:
        for offset, p in shots:
            stamp = str(timedelta(seconds=int(offset)))
            fh.write(f"- {os.path.basename(p)} → {os.path.basename(out_path)} [{stamp}]\n")

    print(f"прикреплено {len(shots)} скриншотов → {out_path}")
    print(f"журнал: {ledger_path}")


if __name__ == "__main__":
    main()
