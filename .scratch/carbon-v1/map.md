# Carbon v1

Type: map

## Destination

A spec for Carbon v1, ready to hand off for implementation: the product design is locked, every technical bet it rests on (capture, detection, diarization, summary) is backed by research or an automated check on public corpora, and icons and UI are agreed. Real-usage tuning comes from the author dogfooding the built app, not from hand-run tests.

## Notes

- Domain: native SwiftUI macOS 26 app, fully on-device meeting transcription. Vocabulary in `GLOSSARY.md`; decisions in `docs/adr/`; research in `docs/research/`.
- Consult `domain-modeling` on every ticket (update `GLOSSARY.md` inline); `prototype` for prototype tickets; `research` for research tickets.
- Standing preferences: native Apple frameworks wherever one exists; keep it simple, no onboarding blabla; US market first; English UI, code and docs; chat with the author in French.
- No hand-run tests or hand-recorded Meetings: the author only uses the built app and reports back. Quality prototypes run fully AFK (public corpora, scripted replay); the human only reacts to the verdict.
- The author owns the product structure and options already validated in "Carbon v1 product design"; technical calls beyond that (detection signals, thresholds, engines, formats) are not theirs to make. Resolve them by research against open-source prior art and official docs, then decide and record the rationale; only bring a question to the author when it changes the product the author validated.
- Overnight 2026-10-27 → 28 the author is away and pre-approves the agent's recommendation on every remaining verdict (prototype outcomes, spec review): take the recommended option, record it, and keep going. Tools available: Orca's built-in browser (`orca` CLI) for web steps and Cloudflare `wrangler` for the Worker + R2. Steps that truly need the author (paid Apple Developer ID, signing identities, secrets only they hold) are listed in a checklist for the morning, never blocked on.
- Tracker: local markdown. Tickets in `issues/`; research findings land in `docs/research/` (the repo is not under git yet, so no `research/<name>` branches).

## Decisions so far

- [Carbon v1 product design](issues/01-carbon-v1-product-design.md): local capture on any Provider, auto-transcribe by default, Me/Them + FluidAudio Speakers and Voice Prints, Foundation Models Summary, Markdown Library + JSON index, Copper-style menu bar UI, Sparkle + Cloudflare distribution.
- [On-device speaker diarization options](issues/02-on-device-diarization.md): FluidAudio offline diarizer (Apache-2.0 / CC-BY weights), embeddings for Voice Prints; French unproven.
- [How local meeting transcribers capture and detect meetings](issues/03-local-meeting-capture.md): mic-in-use + calendar detection; per-bundle tap is novel, browser helpers are the main risk.
- [Native spoken-language detection](issues/04-native-language-detection.md): no public API, so the Meeting Language is picked by the person.
- [Conference data exposed by EventKit events](issues/08-calendar-event-conference-data.md): no conference field; links are parsed from `url`/`location`/`notes` (Meet and Teams live in `notes`), attendees give name + `mailto:` + `isCurrentUser`, and the organizer must be added by hand.
- [Icon board](issues/11-icon-board.md): "Graphene, ultra soft" mark (three soft lattice cells around a dot), flat black on white for now (final in Icon Composer); menu bar glyph's dot turns red while recording.
- [Main window, menus and notification mock](issues/12-main-window-and-menus-mock.md): native split window, Summary notes then "Speaker · 0:19" Transcript, Mail-style participant tokens, Edit opens a window (no inline edit), More = Copy Path / Copy Markdown / Reveal / Delete, Start Transcribing in the menu bar menu, flat notification actions.
- [SpeechTranscriber vs whisper.cpp for Meeting transcription](issues/13-speechtranscriber-vs-whisper-cpp.md): keep SpeechTranscriber live; drop whisper.cpp and WhisperKit; a FluidAudio Parakeet post-Meeting pass is the hybrid to prove on real calls.
- [Audio capture probe across meeting apps](issues/05-audio-capture-probe.md): tap every process owned by the Meeting App (responsible PID, not bundle ID), update the tap live; no-callback fallback only while the app outputs audio; zeros = silence; permission via TCC preflight; Detection ignores Carbon + CoreSpeech; Zoom/Teams from research only.
- [Public meeting corpora for quality tests](issues/16-public-meeting-corpora.md): AMI + QMSum + ICSI (EN) and SUMM-RE + Simsamu (FR) cover most quality tests; the hand-recorded set shrinks to 4 Meetings (EN 1:1, FR 3+, mixed EN/FR, 60 min Zoom with mutes).
- [Prior art in Minute and meeting-transcriber](issues/15-prior-art-minute-and-meeting-transcriber.md): pasrom detects calls by power assertions, diarizes Them only, Voice Print cutoff 0.40 cosine distance; Minute ships chunk-then-merge Summary (4K flagged debug-only); Parakeet not clearly better than Whisper on AMI; reusable scoring code + Jitsi replay test.

## Not yet specified

- Exact Transcript body format in Markdown (Speaker labels, timestamp granularity, how renamed Speakers are written back), once diarization quality is known.
- `meetings.json` schema and Voice Print storage (where, how deletable, privacy wording).
- Behaviour around overlapping or back-to-back Meetings and app crashes mid-Meeting (partial Transcript recovery).
- Landing page and privacy page content for `carbon.alexandrejoly.me`.
- Settings: final layout and copy (the mock only roughs it out), plus a VoiceOver / keyboard / light-mode pass over the whole UI.

## Out of scope

- Hand-recorded Meetings and hand-run Detection checks ([Detection and auto-stop rules on real usage](issues/09-detection-and-auto-stop-tuning.md), hand part of [Real meeting test set](issues/06-real-meeting-test-set.md)): the author won't run them; real-usage tuning comes from dogfooding the built app.

- Implementation itself: the release pipeline (Developer ID, notarization, Sparkle keys, Cloudflare Worker + R2, GitHub Action) and the app build start after this map.
- Later versions (v1.1+): automatic language switching mid-Meeting, echo cancellation, participant names via Accessibility or a browser extension, syncing official Provider transcripts and Gemini summaries, multiple accounts.
- Google Drive / Meet API sync with OAuth, superseded by local capture (`docs/adr/0001-drive-scope-with-unverified-launch.md`).
