# 01: Manual Meeting from the menu bar to a Markdown file

**What to build:** the walking skeleton. Carbon runs as a menu bar app with no Dock icon, showing the "Graphene, ultra soft" glyph. Start Transcribing in its menu captures the microphone as the Me stream with SpeechTranscriber in the system locale, and the glyph's dot turns red. Stop ends the Meeting and writes `~/Documents/Carbon/YYYY/YYYY-MM-DD-slug.md` with the frontmatter and a `## Transcript` of Me Turns, plus the Meeting's entry in `meetings.json`. This ticket sets up the two-part layout from the spec: a `CarbonCore` Swift package with no AppKit or SwiftUI, holding the Recorder orchestrator and its ports, and the app target holding the adapters. It also adds the first Recorder test, driven through fake ports. Spec: "Carbon v1 spec" (`.scratch/carbon-v1/issues/19-carbon-v1-spec.md`), sections Platform and project, Modules (Recorder, Library), Library and `meetings.json`.

**Blocked by:** None (can start immediately).

**Status:** done

- [x] Xcode project for macOS 26, Apple silicon only, `LSUIElement`, not sandboxed, hardened runtime with the audio-input entitlement, bundle ID `me.alexandrejoly.carbon`, and `Design/Carbon.icon` as the App Icon.
- [x] Menu bar glyphs come from the icon board's final SVGs: an 18 pt template glyph when idle, and the red-dot glyph while live.
- [x] Menu: Start Transcribing (or, while live, "Transcribing "<title>"", "since <time>", Stop and Discard), then Reveal in Finder and Quit Carbon ⌘Q.
- [x] At launch, Carbon checks `SpeechTranscriber.isAvailable`; when it is false, Carbon shows one alert and quits.
- [x] The mic stream is converted to the analyzer format, transcribed live with `volatileResults` and `audioTimeRange`, and appended to a CAF file in `InProgress/<id>/`, flushed every 5 s, next to `state.json`.
- [x] Stop writes the file: the slug rules (ASCII-folded, at most 60 characters, `-2` on a collision), frontmatter `provider`, `id` (UUID), `date`, `title` (default "Meeting Oct 23, 9:15 AM"), `duration`, `language` and `participants`, then `## Transcript` built from `**Me** [m:ss] text` Turns. Carbon then deletes the in-progress folder.
- [x] Discard deletes the in-progress folder and writes nothing.
- [x] `meetings.json` uses the spec's version 1 schema, is written atomically, and is backed up to `Backups/` on the first save of each launch and at most once a day after that, keeping the 14 newest copies.
- [x] A Recorder test in `CarbonCore` feeds a fake audio source and replayed Transcriber words, then asserts on the Markdown file and the `meetings.json` written to a temporary Library folder.

**Implementation notes:**

- Layout: `CarbonCore/` (Swift package, tested with `swift test`) and `App/` (adapters and SwiftUI), generated into `Carbon.xcodeproj` by `xcodegen generate` from `project.yml`. The `.xcodeproj`, `App/Info.plist` and `App/Carbon.entitlements` are generated and git-ignored.
- The app's Swift module is `CarbonApp` (the product name stays `Carbon`): a module named `Carbon` collides with Apple's legacy `Carbon.framework`.
- Signing is ad hoc (`CODE_SIGN_IDENTITY: "-"`) until ticket 17 adds the Developer ID. Release builds carry the hardened runtime flag.
- A manual Meeting has no Meeting App, so `provider` is written as `Unknown` until Provider resolution lands (ticket 03). `summary` is `off` in `meetings.json` until ticket 18.
- The recording glyph has a dark-appearance variant (white strokes, `#FF453A` dot) derived from `menubar-recording.svg`, because a non-template black glyph would vanish in a dark menu bar.
- `TranscriptBuilder` only does what this ticket needs (Me words into Turns on a 10 s silence, `m:ss`, capitalized first letter). Ticket 02 owns the full rules and Markdown escaping.
- Backups are named `meetings-<basic ISO 8601, UTC>.json` (e.g. `meetings-20261027T150000Z.json`), so they sort by name and avoid `:` in file names.
- Not checked by hand: a real microphone Meeting end to end, which needs the GUI and the microphone permission. The app builds and launches; the adapters (`MicrophoneSource`, `SpeechTranscriberAdapter`) have no unit tests, by design (spec, Testing Decisions).
