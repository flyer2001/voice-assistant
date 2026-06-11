"""compute_longform_metrics.py — extended metrics для long-form bench.

Beyond classical WER (которая будет inflated ~30-50% против editorial transcript
для всех models), вычисляет:

- WER против normalized editorial transcript (jiwer.wer)
- Term Accuracy — manual aliases list (Amazon Q, Anthropic, GitLab, ...)
- Readability proxy — sentence count, avg sentence length, punct density
- Speaker tags preserved — regex count of RD/DS-style tags
- Topic word overlap — Jaccard на top-50 content words (stopwords filtered)
- Latency / length ratio (chars per sec of inference)

Usage:
    python compute_longform_metrics.py \\
        --input bench/results/longform-2026-06-11.csv \\
        --reference assets/long-form-bench/en/stack-overflow-agents-transcript.txt \\
        --output bench/results/longform-metrics-2026-06-11.csv
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from collections import Counter
from pathlib import Path

try:
    import jiwer
except ImportError:
    print("ERR: jiwer required", file=sys.stderr)
    sys.exit(1)


# Speaker tags (Ryan Donovan / Deepak Singh from editorial transcript)
SPEAKER_TAG_RE = re.compile(r"\b(RD|DS)\b")

# Sentence end punct
SENT_END_RE = re.compile(r"[.!?]+")

PUNCT_RE = re.compile(r"[.,!?:;\-—\"'()«»]")

WORD_RE = re.compile(r"\b[a-zA-Z]+\b")


# Manual term/alias list — key concepts from the Stack Overflow Podcast episode.
# For Term Accuracy: term counted as "correct" if ANY of its aliases appears.
TERM_ALIASES = {
    "amazon_q": ["amazon q", "q developer", "q dev"],
    "bedrock": ["bedrock"],
    "bedrock_agents": ["bedrock agent", "bedrock agents"],
    "aws": ["aws"],
    "ec2": ["ec2"],
    "gitlab": ["gitlab", "git lab"],
    "java": ["java"],
    "react": ["react"],
    "deepak_singh": ["deepak singh", "deepak"],
    "ryan_donovan": ["ryan donovan", "ryan"],
    "genentech": ["genentech"],
    "novacomp": ["novacomp"],
    "genesis": ["genesis"],
    "llm": ["llm", "llms", "language model"],
    "automated_reasoning": ["automated reasoning"],
    "rag": ["rag", "retrieval augmented"],
    "knowledge_base": ["knowledge base", "knowledge bases"],
    "guardrails": ["guardrail", "guardrails"],
    "hallucinat": ["hallucinat"],
    "code_review": ["code review"],
    "agent": ["agent", "agents"],
    "anthropic": ["anthropic"],
    "stack_overflow": ["stack overflow"],
    "biomarker": ["biomarker"],
}


STOPWORDS = set("""
a an the of in on at to for from with by and or but if then else not as is are was were be been being
do does did have has had this that these those it its i you he she we they them their there here
what which who whom where when why how all some any no every much many few more most other some
also just only very even still up down out about over under into through between against than yes no
so do don dont didn doesn ill cant cannot wont can could would should may might shall must will not
me my mine your yours his her hers our ours theirs am s t re ve ll d u o
get got say said see seen know known make made go went going come came one two three four five
""".split())


def normalize(text: str) -> str:
    text = text.lower().strip()
    text = re.sub(r"\s+", " ", text)
    text = re.sub(r"[^a-z0-9\s]", " ", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def compute_wer(reference: str, hypothesis: str) -> float:
    ref = normalize(reference)
    hyp = normalize(hypothesis)
    if not ref or not hyp:
        return 1.0
    try:
        return jiwer.wer(ref, hyp)
    except Exception:
        return 1.0


def compute_term_accuracy(hypothesis: str) -> tuple[int, int, float]:
    h_lower = " " + hypothesis.lower() + " "
    correct = 0
    total = len(TERM_ALIASES)
    for term, aliases in TERM_ALIASES.items():
        if any(a in h_lower for a in aliases):
            correct += 1
    return correct, total, correct / total if total else 0.0


def compute_readability(hypothesis: str) -> dict:
    h = hypothesis.strip()
    if not h:
        return {"sent_count": 0, "avg_sent_len": 0, "punct_density": 0, "char_count": 0, "word_count": 0}
    sentences = [s for s in SENT_END_RE.split(h) if s.strip()]
    sent_count = max(len(sentences), 1)
    words = WORD_RE.findall(h)
    word_count = len(words)
    avg_sent_len = word_count / sent_count
    punct_count = len(PUNCT_RE.findall(h))
    punct_density = punct_count / max(word_count, 1)
    return {
        "sent_count": sent_count,
        "avg_sent_len": round(avg_sent_len, 2),
        "punct_density": round(punct_density, 4),
        "char_count": len(h),
        "word_count": word_count,
    }


def compute_speaker_tags(hypothesis: str) -> int:
    return len(SPEAKER_TAG_RE.findall(hypothesis))


def top_content_words(text: str, top_n: int = 50) -> set[str]:
    words = WORD_RE.findall(text.lower())
    filtered = [w for w in words if w not in STOPWORDS and len(w) >= 4]
    counts = Counter(filtered)
    return {w for w, _ in counts.most_common(top_n)}


def compute_topic_overlap(reference: str, hypothesis: str, top_n: int = 50) -> float:
    ref_set = top_content_words(reference, top_n)
    hyp_set = top_content_words(hypothesis, top_n)
    if not ref_set or not hyp_set:
        return 0.0
    return len(ref_set & hyp_set) / len(ref_set | hyp_set)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True, help="long-form bench CSV")
    p.add_argument("--reference", required=True, help="editorial transcript text")
    p.add_argument("--output", required=True, help="metrics CSV path")
    args = p.parse_args()

    reference = Path(args.reference).read_text(encoding="utf-8")
    print(f"Reference: {len(reference)} chars, {len(WORD_RE.findall(reference))} words")

    rows_in = list(csv.DictReader(open(args.input)))
    print(f"Input rows: {len(rows_in)}")

    out_fields = [
        "model", "file", "run", "chunk_count", "latency_ms", "device", "dtype",
        "wer", "term_correct", "term_total", "term_accuracy",
        "sent_count", "avg_sent_len", "punct_density", "char_count", "word_count",
        "speaker_tags", "topic_jaccard",
        "vram_peak_mb", "ram_peak_mb", "gpu_util_avg_pct",
        "text",
    ]

    with open(args.output, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=out_fields)
        w.writeheader()
        for r in rows_in:
            text = r.get("text", "")
            wer = compute_wer(reference, text)
            t_corr, t_tot, t_acc = compute_term_accuracy(text)
            read = compute_readability(text)
            tags = compute_speaker_tags(text)
            jacc = compute_topic_overlap(reference, text)
            w.writerow({
                "model": r["model"],
                "file": r["file"],
                "run": r["run"],
                "chunk_count": r.get("chunk_count", ""),
                "latency_ms": r.get("latency_ms", ""),
                "device": r.get("device", ""),
                "dtype": r.get("dtype", ""),
                "wer": round(wer, 4),
                "term_correct": t_corr,
                "term_total": t_tot,
                "term_accuracy": round(t_acc, 4),
                "sent_count": read["sent_count"],
                "avg_sent_len": read["avg_sent_len"],
                "punct_density": read["punct_density"],
                "char_count": read["char_count"],
                "word_count": read["word_count"],
                "speaker_tags": tags,
                "topic_jaccard": round(jacc, 4),
                "vram_peak_mb": r.get("vram_peak_mb", ""),
                "ram_peak_mb": r.get("ram_peak_mb", ""),
                "gpu_util_avg_pct": r.get("gpu_util_avg_pct", ""),
                "text": text,
            })

    print(f"Output: {args.output}")


if __name__ == "__main__":
    main()
