"""compute_metrics.py — WER + Term Accuracy + ΔWER из bench CSV.

Reads:
  - bench/ground-truth.json (canonical transcripts + anglicism/number aliases)
  - bench/results/<run>.csv (long-format: model,file,variant,run,text,latency_ms,...)

Writes:
  - bench/results/<run>-metrics.csv (per-row enriched + aggregated per (model, variant))

Metrics:
  - wer: word error rate vs normalized ground truth (jiwer)
  - term_accuracy: fraction of anglicisms correctly recognized (via aliases)
  - number_accuracy: fraction of number targets recognized
  - punctuation_f1: F1 of recovered punct vs ground truth
  - delta_wer_gsm: WER(gsm-variant) - WER(clean-variant) per (model, text)
  - delta_wer_noisy: WER(noisy-variant) - WER(quiet-variant) per (model, text)
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path

try:
    import jiwer
except ImportError:
    print("ERR: jiwer required (pip install jiwer)", file=sys.stderr)
    sys.exit(1)


PUNCT_PATTERN = re.compile(r'[.,!?:;—\-«»"\'`()\[\]{}]')
WHITESPACE_PATTERN = re.compile(r'\s+')


def normalize_text(s: str) -> str:
    """Unicode NFC + lowercase + strip punct + collapse spaces. For WER scoring."""
    s = unicodedata.normalize("NFC", s).lower()
    s = PUNCT_PATTERN.sub(" ", s)
    s = WHITESPACE_PATTERN.sub(" ", s).strip()
    return s


def contains_any_alias(haystack: str, aliases: list[str]) -> bool:
    """Case-insensitive substring match against any form. Both already normalized."""
    h = normalize_text(haystack)
    for alias in aliases:
        if normalize_text(alias) in h:
            return True
    return False


def compute_term_accuracy(model_output: str, anglicisms: list[str], aliases_map: dict[str, list[str]]) -> tuple[int, int, float]:
    """Returns (correct, total, fraction). For each anglicism, check if ANY alias form appears."""
    if not anglicisms:
        return 0, 0, 1.0  # nothing to score, perfect
    correct = sum(1 for term in anglicisms if contains_any_alias(model_output, aliases_map.get(term, [term])))
    return correct, len(anglicisms), correct / len(anglicisms)


def compute_punct_f1(reference: str, hypothesis: str) -> float:
    """F1 на multiset of punctuation chars. Не position-aware (упрощённо)."""
    ref_punct = [c for c in reference if PUNCT_PATTERN.match(c)]
    hyp_punct = [c for c in hypothesis if PUNCT_PATTERN.match(c)]
    if not ref_punct and not hyp_punct:
        return 1.0
    if not ref_punct or not hyp_punct:
        return 0.0
    ref_counts = defaultdict(int)
    for c in ref_punct:
        ref_counts[c] += 1
    hyp_counts = defaultdict(int)
    for c in hyp_punct:
        hyp_counts[c] += 1
    tp = sum(min(ref_counts[c], hyp_counts[c]) for c in ref_counts)
    precision = tp / len(hyp_punct) if hyp_punct else 0.0
    recall = tp / len(ref_punct) if ref_punct else 0.0
    if precision + recall == 0:
        return 0.0
    return 2 * precision * recall / (precision + recall)


def compute_per_row(row: dict, ground_truth: dict) -> dict:
    """Enrich a result row with computed metrics."""
    fname = row["file"]
    if fname.startswith("gsm-"):
        fname = fname[4:]
    text_id = fname.split("-")[0]  # "2a-quiet.wav" → "2a"
    gt = ground_truth["texts"].get(text_id)
    if not gt:
        return row  # unknown text

    model_text = row.get("text", "")
    ref_normalized = gt["normalized"]
    hyp_normalized = normalize_text(model_text)

    enriched = dict(row)
    enriched["wer"] = jiwer.wer(ref_normalized, hyp_normalized) if hyp_normalized else 1.0
    correct, total, term_acc = compute_term_accuracy(
        model_text,
        gt.get("anglicisms", []),
        gt.get("anglicism_aliases", {}),
    )
    enriched["term_correct"] = correct
    enriched["term_total"] = total
    enriched["term_accuracy"] = term_acc

    num_correct, num_total, num_acc = compute_term_accuracy(
        model_text,
        gt.get("numbers", []),
        gt.get("numbers_aliases", {}),
    )
    enriched["number_correct"] = num_correct
    enriched["number_total"] = num_total
    enriched["number_accuracy"] = num_acc

    enriched["punct_f1"] = compute_punct_f1(gt["transcript"], model_text)
    return enriched


def compute_deltas(rows: list[dict]) -> dict[tuple, dict]:
    """For each (model, text_id), compute ΔWER between variants.

    Returns: {(model, text_id): {delta_wer_gsm, delta_wer_noisy}}.
    """
    # Index: (model, text_id, env, codec) → wer
    index = {}
    for r in rows:
        if "wer" not in r:
            continue
        fname = r["file"]
        if fname.startswith("gsm-"):
            fname = fname[4:]
        text_id = fname.split("-")[0]
        env = "noisy" if "noisy" in r["file"] else "quiet"
        codec = r.get("codec", "clean")  # bench script must set this
        key = (r["model"], text_id, env, codec)
        index.setdefault(key, []).append(r["wer"])

    # Average WER over runs
    avg = {k: sum(v) / len(v) for k, v in index.items()}

    deltas = {}
    for (model, text_id, env, codec), wer in avg.items():
        d = deltas.setdefault((model, text_id), {})
        if codec == "clean":
            other = avg.get((model, text_id, env, "gsm"))
            if other is not None:
                d.setdefault("delta_wer_gsm", []).append(other - wer)
        if env == "quiet":
            other = avg.get((model, text_id, "noisy", codec))
            if other is not None:
                d.setdefault(f"delta_wer_noisy_{codec}", []).append(other - wer)

    # Average across multiple text variants if applicable
    return {k: {kk: sum(vv) / len(vv) for kk, vv in v.items()} for k, v in deltas.items()}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--ground-truth", default="bench/ground-truth.json")
    p.add_argument("--input", required=True, help="bench results CSV")
    p.add_argument("--output", required=True, help="enriched CSV output")
    args = p.parse_args()

    gt = json.loads(Path(args.ground_truth).read_text())

    with open(args.input, encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    enriched = [compute_per_row(r, gt) for r in rows]
    deltas = compute_deltas(enriched)

    # Attach deltas to first row per (model, text_id) for convenience
    seen = set()
    for r in enriched:
        fname = r["file"]
        if fname.startswith("gsm-"):
            fname = fname[4:]
        text_id = fname.split("-")[0]
        key = (r["model"], text_id)
        if key not in seen and key in deltas:
            r.update({f"agg_{k}": v for k, v in deltas[key].items()})
            seen.add(key)

    fieldnames = sorted({k for r in enriched for k in r})
    with open(args.output, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(enriched)

    print(f"→ {args.output}: {len(enriched)} rows, {len(deltas)} (model,text) deltas")


if __name__ == "__main__":
    main()
