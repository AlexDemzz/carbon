# On-device summary quality

Type: prototype
Status: open
Blocked by:
Assignee: alexandre

## Question

Does Apple Foundation Models, with chunk-then-merge summarization within its 4K context, produce a Summary (key points, next steps) good enough for v1 on the real meeting test set, in English and French, and how long does it take for a 1-hour Meeting? Outcome: ship as designed / adjust format / drop the Summary from v1.

## Context from "Prior art in Minute and meeting-transcriber"

See `docs/research/prior-art-minute-meeting-transcriber.md` and the ticket's Answer for what shipped code already settles here; only the hand-run checks it lists remain.
Can run on public transcripts (AMI/QMSum, ICSI, SUMM-RE; see "Public meeting corpora for quality tests") without waiting on "Real meeting test set". Minute's chunk-then-merge design is the starting point; Minute flags 4K context as debug-only.

## Progress (2026-10-28, still open)

- Harness: [`prototypes/summary-eval/`](../prototypes/summary-eval/README.md). Two chunk-then-merge variants (Minute's rolling deltas, and map-reduce), guided generation, token counts from the model, per-pass timings; ROUGE scorer against the AMI/ICSI/QMSum references with an extractive anchor; blind judge rubric. The ship / adjust / drop bar is written in the README before any run.
- **Blocked, not resolved:** the on-device model never became available on this Mac overnight (`modelNotReady` for 90 min, then `ModelManagerError 1019` on a request) although Apple Intelligence is enabled. No Summary was generated, so there is no verdict to take: picking ship / adjust / drop without a run would be a guess.
- To finish: once System Settings › Apple Intelligence & Siri shows the model ready, run `./run-all.sh` and `score.py`, judge with `judge-rubric.md`, then apply the bar. Fully AFK after that one check.
