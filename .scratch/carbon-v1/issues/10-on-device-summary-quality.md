# On-device summary quality

Type: prototype
Status: resolved
Blocked by:
Assignee: alexandre

## Question

Does Apple Foundation Models, with chunk-then-merge summarization within its 4K context, produce a Summary (key points, next steps) good enough for v1 on the real meeting test set, in English and French, and how long does it take for a 1-hour Meeting? Outcome: ship as designed / adjust format / drop the Summary from v1.

## Context from "Prior art in Minute and meeting-transcriber"

See `docs/research/prior-art-minute-meeting-transcriber.md` and the ticket's Answer for what shipped code already settles here; only the hand-run checks it lists remain.
Can run on public transcripts (AMI/QMSum, ICSI, SUMM-RE; see "Public meeting corpora for quality tests") without waiting on "Real meeting test set". Minute's chunk-then-merge design is the starting point; Minute flags 4K context as debug-only.

## Answer

Resolved 2026-10-28, fully AFK. The author pre-approved the recommendation (map Notes, overnight).

**Verdict: drop the Summary from v1.** The bar fixed in the harness README before the run says drop when mean usefulness is below 3 in either language. Both variants land below 3 in both languages, and both make more than the allowed one wrong item per Summary. Speed is not the problem.

The run covered all 18 AMI, ICSI and SUMM-RE Meetings (10 EN, 8 FR, 17–79 min) through both variants, on the reference Transcript rendered the way Carbon writes it. The model reports an 8,192-token context on this Mac (macOS 27), not 4K. Each Summary was scored blind by an LLM judge reading the full Transcript, against `judge-rubric.md`, with the variant labels shuffled.

| | usefulness (1–5) | wrong items / Summary | next steps (1–5) | noise | ≥ 4 usefulness |
|---|---:|---:|---:|---:|---:|
| English, rolling | 2.7 | 2.3 | 2.2 | 2.3 | 2 / 10 |
| English, map-reduce | 2.7 | 1.6 | 2.2 | 1.9 | 0 / 10 |
| French, rolling | 2.1 | 2.4 | 1.6 | 2.0 | 0 / 8 |
| French, map-reduce | 2.9 | 1.4 | 2.1 | 0.6 | 1 / 8 |

- **Next steps are the main failure.** Both variants turn ideas that were raised, rejected or already settled into tasks, and they almost never name an owner. On Meetings with no action at all (a round of pitches, an exchange of experiences), every next step is invented.
- **Key points carry wrong facts.** Examples: the wrong venue (a cinema rather than the chosen drive-in), the wrong date ("octobre ou janvier" instead of 8 May), the budget given as the cost, a rejected option kept as the plan, a self-corrected fact kept in its first form (Stanford rather than Cambridge), and a team that was never mentioned. Wrong owners and numbers are exactly what a person would act on.
- **Map-reduce is the better variant** (fewer wrong items, much less noise in French), but even it passes neither language. Dropping next steps ("adjust format") would not rescue it: key points alone still carry 1.4–1.6 wrong items per Summary, above the bar's one.
- **Failures.** 2 of 18 Meetings had a failed pass, so the Summary came out partial:
  - ICSI Bmr006, rolling: generation ran away past the 8,192-token context on a 4.6K-token chunk.
  - SUMM-RE 032b, both variants: guardrail "May contain unsafe content" on a harmless student debate about phone overuse, harassment and phone theft.
  
  For rolling that is above the bar's 1 in 10. The guardrail false positive matters most for real Meetings, because nothing in the app can work around it.
- **Language and speed pass.** Every Summary was written entirely in the Meeting Language. A Meeting takes 48–145 s per hour of audio, and 174 s/h at worst (the 79 min ICSI Meeting with the overflow), all under the 3 min bar.
- **ROUGE (sanity check, EN only).** Both variants beat the longest-turns extractive anchor: R1 0.31–0.33 against 0.23–0.24 on the AMI/ICSI abstractive references, and 0.29–0.31 against 0.19–0.20 on QMSum. So the model does track topics. The failure is in faithfulness, which ROUGE does not measure.

**Consequences for the spec.** The spec's own drop path applies, with nothing else changed. The Summarizer port gets a no-op adapter, `summary` is `off` in `meetings.json`, `## Summary` is never written, and the Meeting panel shows no notes section. The port stays, so a better on-device model can be plugged in later without touching the Library, the Recorder or the UI. An on-device Summary returns as a v1.1+ question, to be re-run with this harness when Apple ships a stronger model. The Transcript stays the product: the person's own agent summarizes it.

## Assets

- Harness and bar: [`prototypes/summary-eval/README.md`](../prototypes/summary-eval/README.md)
- Generated Summaries and per-pass logs: `prototypes/summary-eval/results/<meeting>.<variant>.{md,json}`, plus `run.log`
- Blind judge scores (one JSON per Meeting) and the X/Y key: `prototypes/summary-eval/results/judge/`
- ROUGE rows: `prototypes/summary-eval/results/rouge.json`
