# Detection and auto-stop rules on real usage

Type: prototype
Status: out of scope
Blocked by: 17

## Question

Do the chosen rules (mic held >15 s by a non-ignored process; stop when mic released + 30 s silence + event ended, or 10 min silence without event) behave correctly across real situations: muting in Meet, Zoom holding the mic between back-to-back calls, a Slack huddle, a dictation app, a voice memo, overlapping calendar events? Outcome: final thresholds and the initial ignored-apps list.

## Context from "Audio capture probe across meeting apps"

- Already settled: ignore Carbon and `com.apple.CoreSpeech` (case-insensitive) in mic-in-use, and don't count CoreSpeech when deciding a Meeting ended.
- To check here: Zoom keeping the mic between back-to-back calls, and Teams holding it while idle (sources disagree, see `docs/research/native-meeting-app-audio-processes.md`). Mic-in-use alone may need a calendar event or the Meeting App's audio output to start a Meeting for these two.

## Context from "Prior art in Minute and meeting-transcriber"

See `docs/research/prior-art-minute-meeting-transcriber.md` and the ticket's Answer for what shipped code already settles here; only the hand-run checks it lists remain.

## Out of scope (2026-10-27)

The author won't run hand checks; thresholds are tuned by dogfooding the built app. The initial rules are picked in "Power assertions as a Detection signal" from prior art.
