# 01: Manual Meeting from the menu bar to a Markdown file

**What to build:** the walking skeleton. Carbon runs as a menu bar app with no Dock icon, showing the "Graphene, ultra soft" glyph. Start Transcribing in its menu captures the microphone as the Me stream with SpeechTranscriber in the system locale, and the glyph's dot turns red. Stop ends the Meeting and writes `~/Documents/Carbon/YYYY/YYYY-MM-DD-slug.md` with the frontmatter and a `## Transcript` of Me Turns, plus the Meeting's entry in `meetings.json`. This ticket sets up the two-part layout from the spec: a `CarbonCore` Swift package with no AppKit or SwiftUI, holding the Recorder orchestrator and its ports, and the app target holding the adapters. It also adds the first Recorder test, driven through fake ports. Spec: "Carbon v1 spec" (`.scratch/carbon-v1/issues/19-carbon-v1-spec.md`), sections Platform and project, Modules (Recorder, Library), Library and `meetings.json`.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] Xcode project for macOS 26, Apple silicon only, `LSUIElement`, not sandboxed, hardened runtime with the audio-input entitlement, bundle ID `me.alexandrejoly.carbon`, and `Design/Carbon.icon` as the App Icon.
- [ ] Menu bar glyphs come from the icon board's final SVGs: an 18 pt template glyph when idle, and the red-dot glyph while live.
- [ ] Menu: Start Transcribing (or, while live, "Transcribing "<title>"", "since <time>", Stop and Discard), then Reveal in Finder and Quit Carbon ⌘Q.
- [ ] At launch, Carbon checks `SpeechTranscriber.isAvailable`; when it is false, Carbon shows one alert and quits.
- [ ] The mic stream is converted to the analyzer format, transcribed live with `volatileResults` and `audioTimeRange`, and appended to a CAF file in `InProgress/<id>/`, flushed every 5 s, next to `state.json`.
- [ ] Stop writes the file: the slug rules (ASCII-folded, at most 60 characters, `-2` on a collision), frontmatter `provider`, `id` (UUID), `date`, `title` (default "Meeting Oct 23, 9:15 AM"), `duration`, `language` and `participants`, then `## Transcript` built from `**Me** [m:ss] text` Turns. Carbon then deletes the in-progress folder.
- [ ] Discard deletes the in-progress folder and writes nothing.
- [ ] `meetings.json` uses the spec's version 1 schema, is written atomically, and is backed up to `Backups/` on the first save of each launch and at most once a day after that, keeping the 14 newest copies.
- [ ] A Recorder test in `CarbonCore` feeds a fake audio source and replayed Transcriber words, then asserts on the Markdown file and the `meetings.json` written to a temporary Library folder.
