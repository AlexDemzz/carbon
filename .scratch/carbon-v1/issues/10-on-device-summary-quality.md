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
