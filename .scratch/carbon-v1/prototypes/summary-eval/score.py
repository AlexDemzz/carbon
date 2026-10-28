# PROTOTYPE, throwaway. ROUGE of each generated Summary against the test set's reference summaries,
# next to an extractive anchor (the longest transcript turns, cut to the same word count).
# Usage: uv run --with rouge-score python score.py <test set dir> <results dir>
import json
import re
import sys
from pathlib import Path
from statistics import mean

from rouge_score import rouge_scorer

test_set, results = Path(sys.argv[1]), Path(sys.argv[2])
scorer = rouge_scorer.RougeScorer(["rouge1", "rouge2", "rougeLsum"], use_stemmer=True)


def references(meeting: Path) -> dict[str, str]:
    text = (meeting / "reference/summary.md").read_text()
    sections = dict(re.findall(r"^## (.+?)\n(.*?)(?=^## |\Z)", text, re.S | re.M))
    abstractive = "\n".join(
        sections.get(k, "") for k in ("Abstract", "Decisions", "Actions") if "NA." not in sections.get(k, "")
    )
    return {"abstractive": abstractive, "qmsum": sections.get("QMSum general summary", "")}


def candidate(markdown: str) -> str:
    return "\n".join(l[2:] for l in markdown.splitlines() if l.startswith("- ") and l != "- (none)")


def longest_turns(meeting: Path, words: int) -> str:
    rows = [json.loads(l) for l in (meeting / "reference/segments.jsonl").read_text().splitlines()]
    turns = sorted((r["text"] for r in rows if r["text"]), key=len, reverse=True)
    out, n = [], 0
    for t in turns:
        if n >= words:
            break
        out.append(t)
        n += len(t.split())
    return "\n".join(out)


def f(ref: str, cand: str) -> dict[str, float]:
    s = scorer.score(ref, cand)
    return {k: round(v.fmeasure, 3) for k, v in s.items()}


rows = []
for run in sorted(results.glob("*.*.json")):
    log = json.loads(run.read_text())
    meeting = test_set / "meetings" / log["meeting"]
    if log["language"] != "en":
        continue
    cand = candidate(run.with_suffix(".md").read_text())
    anchor = longest_turns(meeting, len(cand.split()))
    for name, ref in references(meeting).items():
        if not ref.strip():
            continue
        rows.append({"meeting": log["meeting"], "variant": log["variant"], "reference": name,
                     "summary": f(ref, cand), "longest_turns": f(ref, anchor)})

print(f"{'meeting':16} {'variant':10} {'ref':12} {'R1':>6} {'R2':>6} {'RL':>6}   anchor R1/R2/RL")
for r in rows:
    s, a = r["summary"], r["longest_turns"]
    print(f"{r['meeting']:16} {r['variant']:10} {r['reference']:12} {s['rouge1']:6} {s['rouge2']:6} {s['rougeLsum']:6}"
          f"   {a['rouge1']}/{a['rouge2']}/{a['rougeLsum']}")
print()
for variant in sorted({r["variant"] for r in rows}):
    for ref in ("abstractive", "qmsum"):
        sel = [r for r in rows if r["variant"] == variant and r["reference"] == ref]
        if sel:
            m = {k: round(mean(r["summary"][k] for r in sel), 3) for k in ("rouge1", "rouge2", "rougeLsum")}
            a = {k: round(mean(r["longest_turns"][k] for r in sel), 3) for k in ("rouge1", "rouge2", "rougeLsum")}
            print(f"mean {variant:10} {ref:12} summary {m}  anchor {a}")
(results / "rouge.json").write_text(json.dumps(rows, indent=1))
