# Summary eval (PROTOTYPE, throwaway)

Answers the ticket "On-device summary quality" (`../../issues/10-on-device-summary-quality.md`): Apple Foundation Models, chunk-then-merge inside its context window, on the real meeting test set (`~/Datasets/carbon-test-set`).

Input is the reference transcript (`reference/segments.jsonl`) written the way Carbon will write a Transcript: `Me` / `Speaker A…`, consecutive turns merged. So the run judges the Summary step alone, on a perfect Transcript; ASR errors come on top in the real app.

## Run

```sh
./run-all.sh      # builds ./summarize, then every AMI, ICSI and SUMM-RE Meeting, both variants
./summarize ~/Datasets/carbon-test-set/meetings/ami-ES2004a rolling results   # one Meeting
uv run --with rouge-score python score.py ~/Datasets/carbon-test-set results
```

Variants:

- `rolling`: Minute's design. Each pass gets the accepted Summary and one transcript chunk and returns net-new key points and next steps; code merges them (containment dedupe, keep the longer).
- `mapreduce`: each chunk gets independent notes, then one reduce pass (more rounds if the notes overflow) writes the final 3–8 key points and next steps.

Both use guided generation (`@Generable`), greedy sampling, a fresh session per pass, and token counts from `SystemLanguageModel.tokenCount(for:)`.

## Bar, fixed before the run

Judged per Meeting by a blind rubric (`judge-rubric.md`), 1–5 for usefulness, plus counts of wrong or unsupported items:

- **Ship as designed** if, in both English and French: mean usefulness ≥ 3.5, on average ≤ 1 unsupported or wrong item per Summary, no run fails outright (context overflow, guardrail, wrong language), and a 1 h Meeting takes ≤ 3 min on this M3 Pro.
- **Adjust format** if key points pass but next steps (or the length/structure) do not, or if one variant clearly beats the other and changes the design.
- **Drop the Summary from v1** if mean usefulness < 3 in either language, or runs fail on more than 1 in 10 Meetings.

ROUGE against the AMI/ICSI abstractive and QMSum references is reported next to an extractive anchor (the longest transcript turns at the same length) as a sanity check, not as the bar: ROUGE on meeting summaries is low for every system.

## Status (2026-10-28)

Run on all 18 Meetings, both variants, with an 8,192-token context. Verdict: **drop the Summary from v1**. Mean usefulness is 2.7 in English for both variants, and 2.1 (rolling) and 2.9 (map-reduce) in French. That is under 3 in both languages, with 1.4–2.4 wrong items per Summary. Speed passes at ≤ 174 s per hour of audio. Full numbers and examples are in the ticket's Answer. The judge scores are in `results/judge/`, with `key.json` mapping X/Y to variants.
