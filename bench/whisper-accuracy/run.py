#!/usr/bin/env python3
"""Прогон сохранённого корпуса .ogg через STT-эндпоинты + WER.

Корпус собирается из audit.jsonl — те самые файлы, что бот реально принял,
вместе с транскриптом, который тогда получился.

    ./run.py transcribe                      # прогнать через дефолтный endpoint
    ./run.py transcribe --endpoint turbo=http://192.168.88.13:8000
    ./run.py report                          # WER против ground-truth.jsonl
    ./run.py groundtruth                     # создать заготовку для разметки

WER считается по словам (Левенштейн), без внешних зависимостей.
Ground truth заполняется руками — без него это только сравнение моделей
между собой, не accuracy.
"""
import argparse
import json
import os
import re
import subprocess
import sys
from datetime import date

HERE = os.path.dirname(os.path.abspath(__file__))
AUDIT = "/var/lib/voice-bot/audit.jsonl"
GROUND = os.path.join(HERE, "ground-truth.jsonl")
DEFAULT_ENDPOINT = "turbo=http://192.168.88.13:8000"
PUBLIC_BASE = "https://cashflow-game.ru/voice-out/accuracy"


def load_corpus():
    """(msg_id, path, duration_s, historical_transcript) для существующих файлов."""
    out = []
    with open(AUDIT) as fh:
        for line in fh:
            try:
                e = json.loads(line)
            except Exception:
                continue
            p = e.get("audio_path")
            if not p or not os.path.exists(p):
                continue
            out.append({
                "msg_id": e.get("msg_id"),
                "path": p,
                "duration_s": e.get("duration_s"),
                "historical": (e.get("transcript_whisper")
                               or e.get("transcript_vk") or ""),
                "historical_stt_ms": e.get("stt_ms"),
                "ts": e.get("ts"),
            })
    out.sort(key=lambda c: c["ts"] or "")
    return out


def normalize(text):
    """Для WER: lowercase, без пунктуации, схлопнутые пробелы. ё→е."""
    t = (text or "").lower().replace("ё", "е")
    t = re.sub(r"[^\w\s]", " ", t, flags=re.UNICODE)
    return t.split()


def wer(ref_words, hyp_words):
    """(errors, ref_len). Классический word-level Левенштейн."""
    n, m = len(ref_words), len(hyp_words)
    if n == 0:
        return (m, 0)
    prev = list(range(m + 1))
    for i in range(1, n + 1):
        cur = [i] + [0] * m
        for j in range(1, m + 1):
            cost = 0 if ref_words[i - 1] == hyp_words[j - 1] else 1
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        prev = cur
    return (prev[m], n)


def transcribe_one(url, path, lang="ru"):
    """curl вместо requests — на VDS нет лишних пакетов, а curl есть всегда."""
    cmd = ["curl", "-s", "--max-time", "180",
           "-F", f"audio=@{path}", "-F", f"lang_hint={lang}",
           f"{url.rstrip('/')}/transcribe"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        return {"error": f"curl exit {r.returncode}: {r.stderr[:200]}"}
    try:
        return json.loads(r.stdout)
    except Exception:
        return {"error": f"bad json: {r.stdout[:200]}"}


def cmd_transcribe(args):
    endpoints = dict(e.split("=", 1) for e in args.endpoint)
    corpus = load_corpus()
    print(f"corpus: {len(corpus)} clips, "
          f"{sum(c['duration_s'] or 0 for c in corpus)}s audio")

    out_path = os.path.join(HERE, f"results-{date.today()}.jsonl")
    with open(out_path, "w") as out:
        for i, clip in enumerate(corpus, 1):
            row = dict(clip)
            row["runs"] = {}
            for name, url in endpoints.items():
                res = transcribe_one(url, clip["path"], args.lang)
                row["runs"][name] = res
                mark = "!" if res.get("error") else " "
                text = res.get("error") or res.get("text", "")
                print(f"{mark}[{i:>2}/{len(corpus)}] msg={clip['msg_id']} "
                      f"{name} {res.get('stt_ms', '?')}ms | {text[:70]}")
            out.write(json.dumps(row, ensure_ascii=False) + "\n")
    print(f"\n→ {out_path}")
    return out_path


def latest_results():
    """Последний results-*.jsonl → {msg_id: лучший распознанный текст}."""
    files = sorted(f for f in os.listdir(HERE) if f.startswith("results-"))
    if not files:
        return {}
    best = {}
    for line in open(os.path.join(HERE, files[-1])):
        try:
            r = json.loads(line)
        except Exception:
            continue
        texts = [v.get("text", "") for v in (r.get("runs") or {}).values()]
        texts = [t for t in texts if t]
        if texts:
            best[r["msg_id"]] = max(texts, key=len)
    return best


def cmd_groundtruth(args):
    """Заготовка для ручной разметки.

    draft берём из свежего прогона, а не из audit.jsonl: часть исторических
    транскриптов пустые (STT тогда падал), править там нечего.
    """
    if os.path.exists(GROUND) and not args.force:
        print(f"{GROUND} уже есть, --force чтобы перезаписать")
        return
    corpus = load_corpus()
    fresh = latest_results()
    with open(GROUND, "w") as fh:
        for c in corpus:
            fh.write(json.dumps({
                "msg_id": c["msg_id"],
                "duration_s": c["duration_s"],
                "audio": f"{PUBLIC_BASE}/{os.path.basename(c['path'])}",
                "draft": fresh.get(c["msg_id"]) or c["historical"],
                "truth": "",
            }, ensure_ascii=False) + "\n")
    print(f"→ {GROUND} ({len(corpus)} строк)\n"
          "Заполни поле truth тем, что реально сказано. draft — что распознал\n"
          "бот тогда, правь его, а не пиши с нуля. Пустой truth = клип пропущен.")


def cmd_merge(args):
    """Влить прогон, сделанный не через HTTP (например mlx на маке).

    Ожидает JSON-список [{"msg_id": int, "text": str, "stt_ms": int}, ...].
    Лишние msg_id (файлы вне корпуса) игнорируются.
    """
    files = sorted(f for f in os.listdir(HERE) if f.startswith("results-"))
    if not files:
        sys.exit("нет results-*.jsonl — сначала ./run.py transcribe")
    path = os.path.join(HERE, files[-1])

    external = {r["msg_id"]: r for r in json.load(open(args.file))}
    rows, merged = [], 0
    for line in open(path):
        if not line.strip():
            continue
        r = json.loads(line)
        ext = external.get(r["msg_id"])
        if ext:
            r.setdefault("runs", {})[args.name] = {
                k: v for k, v in ext.items() if k != "msg_id"}
            merged += 1
        rows.append(r)
    with open(path, "w") as fh:
        for r in rows:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"влито {merged} записей как '{args.name}' → {path}")
    unused = set(external) - {r["msg_id"] for r in rows}
    if unused:
        print(f"не из корпуса, пропущены: {sorted(unused)}")


def cmd_disagree(args):
    """Где модели разошлись — кандидаты на ошибку, до всякой разметки."""
    files = sorted(f for f in os.listdir(HERE) if f.startswith("results-"))
    if not files:
        sys.exit("нет results-*.jsonl")
    path = os.path.join(HERE, files[-1])
    rows = [json.loads(l) for l in open(path) if l.strip()]
    names = sorted({n for r in rows for n in r.get("runs", {})})
    if len(names) < 2:
        sys.exit(f"нужно ≥2 прогона, есть: {names or 'ни одного'}")

    print(f"# Расхождения между {' и '.join(names)}\n")
    shown = 0
    for r in rows:
        texts = {n: (r["runs"].get(n, {}) or {}).get("text", "") for n in names}
        words = {n: normalize(t) for n, t in texts.items()}
        base = names[0]
        for n in names[1:]:
            e, ln = wer(words[base], words[n])
            if e == 0:
                continue
            shown += 1
            print(f"## msg {r['msg_id']} ({r.get('duration_s')}s) — "
                  f"{e} слов из {ln} расходятся")
            for name in names:
                print(f"  {name:<16} {texts[name]!r}")
            print()
    print(f"расходятся на {shown} из {len(rows)} клипов")


def cmd_report(args):
    if not os.path.exists(GROUND):
        sys.exit(f"нет {GROUND} — сначала ./run.py groundtruth и заполни truth")
    truth = {}
    for line in open(GROUND):
        try:
            r = json.loads(line)
        except Exception:
            continue
        if r.get("truth", "").strip():
            truth[r["msg_id"]] = r["truth"]

    results = args.results or sorted(
        f for f in os.listdir(HERE) if f.startswith("results-"))[-1:]
    if not results:
        sys.exit("нет results-*.jsonl — сначала ./run.py transcribe")
    path = results if isinstance(results, str) else os.path.join(HERE, results[-1])

    rows = [json.loads(l) for l in open(path) if l.strip()]
    names = sorted({n for r in rows for n in r.get("runs", {})})
    print(f"# WER — {path}")
    print(f"размечено: {len(truth)} из {len(rows)} клипов\n")

    totals = {n: [0, 0] for n in names + ["historical"]}
    print("| msg_id | " + " | ".join(names + ["historical"]) + " |")
    print("|---" * (len(names) + 2) + "|")
    for r in rows:
        if r["msg_id"] not in truth:
            continue
        ref = normalize(truth[r["msg_id"]])
        cells = []
        for n in names + ["historical"]:
            hyp = (r["historical"] if n == "historical"
                   else r["runs"].get(n, {}).get("text", ""))
            e, ln = wer(ref, normalize(hyp))
            totals[n][0] += e
            totals[n][1] += ln
            cells.append(f"{e/ln*100:.0f}%" if ln else "-")
        print(f"| {r['msg_id']} | " + " | ".join(cells) + " |")

    print("\n## Итого")
    for n in names + ["historical"]:
        e, ln = totals[n]
        print(f"- {n}: WER {e/ln*100:.1f}% ({e} ошибок / {ln} слов)"
              if ln else f"- {n}: нет данных")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    t = sub.add_parser("transcribe")
    t.add_argument("--endpoint", action="append", default=None,
                   help="name=url, можно несколько")
    t.add_argument("--lang", default="ru")
    t.set_defaults(fn=cmd_transcribe)

    g = sub.add_parser("groundtruth")
    g.add_argument("--force", action="store_true")
    g.set_defaults(fn=cmd_groundtruth)

    m = sub.add_parser("merge")
    m.add_argument("name", help="как назвать прогон, напр. mac-large-v3")
    m.add_argument("file", help="JSON-список [{msg_id, text, stt_ms}]")
    m.set_defaults(fn=cmd_merge)

    d = sub.add_parser("disagree")
    d.set_defaults(fn=cmd_disagree)

    r = sub.add_parser("report")
    r.add_argument("--results", default=None)
    r.set_defaults(fn=cmd_report)

    args = ap.parse_args()
    if getattr(args, "endpoint", None) is None and args.cmd == "transcribe":
        args.endpoint = [DEFAULT_ENDPOINT]
    args.fn(args)


if __name__ == "__main__":
    main()
