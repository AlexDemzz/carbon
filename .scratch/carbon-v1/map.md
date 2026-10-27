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
- App icon: `Design/Carbon.icon` (Icon Composer document, flat black mark on white in light and dark) is the icon to package in the app; `Design/mark.svg` is the flat logo for the website.
- Website: https://carbon.alexandrejoly.me is live (alexandrejoly.me monorepo, `apps/carbon`, video in `apps/carbon-video` via Remotion). Its "Download Carbon for Mac" button points to `https://carbon.alexandrejoly.me/download`: the release pipeline must serve the latest DMG there (or change `DOWNLOAD_URL` in `apps/carbon/src/lib/site.ts`).
- Tracker: local markdown. Tickets in `issues/`; research findings land in `docs/research/` on `main`. The repo is git, private on GitHub (`AlexDemzz/carbon`, open-sourced later): commit and push each resolved ticket to `main`; keep corpora and large downloads outside the repo.

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
- [Real meeting test set](issues/06-real-meeting-test-set.md): 28 public-corpus Meetings in `~/Datasets/carbon-test-set` (AMI ES2004/ES2011 series, ICSI Bed016 + Bmr006, SUMM-RE dev incl. Zoom, Simsamu) as aligned Me/Them WAVs + RTTM/words/summary references; no live-call replay.
- [Power assertions as a Detection signal](issues/17-power-assertions-as-detection-signal.md): Zoom/Teams/Webex call assertions join the mic as start signals (each alone auto-starts) and end a Meeting on release; browser WebRTC assertion is diagnostic only; 15 s / 3 s×2 confirm, 15 s grace + 30 s silence, 5 s back-to-back gap, 4 h cap; ~40 Ignored Apps.

## Not yet specified

- Exact Transcript body format in Markdown (Speaker labels, timestamp granularity, how renamed Speakers are written back), once diarization quality is known.
- `meetings.json` schema and Voice Print storage (where, how deletable, privacy wording).
- Behaviour around overlapping Meetings (two call apps at once) and app crashes mid-Meeting (partial Transcript recovery); back-to-back splitting is decided in "Power assertions as a Detection signal".
- Landing page and privacy page content for `carbon.alexandrejoly.me`.
- Settings: final layout and copy (the mock only roughs it out), plus a VoiceOver / keyboard / light-mode pass over the whole UI.

## Out of scope

- Hand-recorded Meetings and hand-run Detection checks ([Detection and auto-stop rules on real usage](issues/09-detection-and-auto-stop-tuning.md), hand part of [Real meeting test set](issues/06-real-meeting-test-set.md)): the author won't run them; real-usage tuning comes from dogfooding the built app.

- Implementation itself: the release pipeline (Developer ID, notarization, Sparkle keys, Cloudflare Worker + R2, GitHub Action) and the app build start after this map.
- Later versions (v1.1+): automatic language switching mid-Meeting, echo cancellation, participant names via Accessibility or a browser extension, syncing official Provider transcripts and Gemini summaries, multiple accounts.
- Google Drive / Meet API sync with OAuth, superseded by local capture (`docs/adr/0001-drive-scope-with-unverified-launch.md`).
