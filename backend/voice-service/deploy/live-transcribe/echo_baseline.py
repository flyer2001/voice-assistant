#!/usr/bin/env python3
"""Сколько эха своего TTS в расшифровках и не режет ли фильтр живую речь.

Мерилка к echo_filter.py: прогоняет его правила по всему архиву
(`/srv/voice-out/*.json` × конспекты `/srv/voice-private/live/*.md`) и печатает
каждую пару, которую фильтр счёл эхом. Решает человек: ложное срабатывание
здесь — это минута эфира, помеченная чужой меткой, и такого должно быть ноль.

Запускать после любой правки порогов в echo_filter.py:

    python3 echo_baseline.py                  # текущие пороги
    python3 echo_baseline.py --min-run 30     # посмотреть, что развалится

Окно по времени тут не применяется сознательно: имена записей идут по часам
мака, файлы TTS — по UTC, смещение между ними эмпирическое. Прогон без окна —
худший случай, и пороги должны держать FP = 0 даже на нём.
"""
import argparse
import glob
import importlib.util
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "ef", os.path.join(HERE, "echo_filter.py"))
ef = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ef)

LIVE = "/srv/voice-private/live"
BLOCK_RE = re.compile(r"^\*\*\[(\d\d:\d\d:\d\d)\]\*\*\s*(?:_([^_]+):_)?\s*(.*)$")


def load_tts(d):
    items = []
    for p in sorted(glob.glob(os.path.join(d, "*.json"))):
        try:
            with open(p) as f:
                text = json.load(f).get("text") or ""
        except (OSError, ValueError):
            continue
        n = ef.norm(text)
        if n:
            items.append((os.path.basename(p), n, text.strip()))
    return items


def load_blocks(d):
    blocks = []
    for p in sorted(glob.glob(os.path.join(d, "*.md"))):
        name = os.path.basename(p)
        if ".summary" in name or not name[:4].isdigit():
            continue
        with open(p) as f:
            for line in f:
                m = BLOCK_RE.match(line.rstrip("\n"))
                if m and m.group(3).strip():
                    blocks.append((name, m.group(1), m.group(3).strip()))
    return blocks


def tokens(s):
    return {w for w in s.split() if len(w) >= 5}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--live", default=LIVE)
    ap.add_argument("--tts-dir", default=ef.VOICE_OUT)
    ap.add_argument("--min-run", type=int, default=ef.MIN_RUN)
    ap.add_argument("--min-cov", type=float, default=ef.MIN_COVERAGE)
    a = ap.parse_args()

    tts = load_tts(a.tts_dir)
    blocks = load_blocks(a.live)
    print(f"TTS-фраз: {len(tts)}   блоков: {len(blocks)}", file=sys.stderr)
    if not tts or not blocks:
        print("нечего мерить — архив недоступен?", file=sys.stderr)
        return 1

    flagged = []
    for bname, tc, btext in blocks:
        bn = ef.norm(btext)
        btok = tokens(bn)
        for fname, tn, raw in tts:
            if len(tokens(tn) & btok) < 2:   # дешёвый префильтр
                continue
            run, cov = ef.match(tn, bn)
            if run >= a.min_run and cov >= a.min_cov:
                flagged.append((run, cov, bname, tc, fname, raw, btext))

    flagged.sort(reverse=True)
    print(f"\nпомечено эхом: {len(flagged)} пар "
          f"(порог: кусок {a.min_run} симв., совпадение {a.min_cov:.0%})")
    for run, cov, bname, tc, fname, raw, btext in flagged:
        print(f"\n[кусок {run}, совпало {cov:.0%}] {bname} {tc} ← {fname}")
        print(f"  TTS:  {raw[:200]}")
        print(f"  блок: {btext[:200]}")
    print("\nСверить глазами: каждая пара выше должна быть реальным эхом. "
          "Живая речь в списке = фильтр съел бы эфир.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
