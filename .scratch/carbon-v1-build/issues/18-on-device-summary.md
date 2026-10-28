# 18: On-device Summary in the file and the panel

**What to build:** each Meeting gets a Summary, written in the Meeting Language, with "Key points" and "Next steps". It is inserted above `## Transcript` once ready, after the Transcript file is already on disk, and shown as notes at the top of the Meeting panel. **Verdict (2026-10-28): drop.** Only the drop path applies: build the no-op Summarizer and the port wiring, and skip the unchecked boxes about the Foundation Models adapter, rendering, retry and panel notes. This ticket applies the verdict of "On-device summary quality" (`.scratch/carbon-v1/issues/10-on-device-summary-quality.md`):
- **ship**: as in the spec, using the variant that ticket picks (rolling or map-reduce);
- **adjust format**: the spec's Summary type and rendering, adjusted per the verdict;
- **drop**: a no-op Summarizer, `summary: "off"`, no section and no notes. In that case only the port wiring lands.

Spec: "Summary (pending …)", UI (Meeting panel).

**Blocked by:** 08 (Main window: Meeting list, search and Meeting panel), 09 (Meeting actions, the editor window, Local Edits and reconcile).

**Status:** ready-for-agent

- [ ] Summarizer adapter: `SystemLanguageModel.default`, guided generation, greedy sampling, a fresh session per pass, line-boundary chunks sized with `tokenCount(for:)` against `contextSize`, and one repair pass on invalid output.
- [ ] The Summary is rendered under `## Summary` with `### Key points` and `### Next steps` (next steps left out when empty). It is inserted only while `## Transcript` exists, and `writtenHash` is kept correct as in Library's surgical-write rule.
- [ ] Unavailable model: `summary: "unavailable"`. Carbon retries oldest first when availability turns available.
- [ ] A guardrail error, overflow or failed repair gives `failed`, with no retry, and the panel shows "No Summary for this Meeting.".
- [ ] The panel shows Key points and Next steps notes above the Transcript.
- [ ] Recorder tests with a Summarizer fake: Summary inserted after the Transcript; unavailable then retried; guardrail failure; a Local Edit before insertion keeps the person's text.
- [ ] The spec's Summary section is updated to the verdict's final shape.
