# How local meeting transcribers detect and capture Meetings on macOS

Researched 2026-10-27 against primary sources: source code at pinned commits, official help centers, and Apple developer documentation. Every claim carries a source link. Anything I could not confirm from a primary source is marked **unverified**. Inferences I drew from a source, which the source does not state outright, are marked **(inference)**.

Carbon's plan, for reference ([ADR-0003](../adr/0003-local-capture-instead-of-provider-sync.md)): detect which app uses the mic (`kAudioHardwarePropertyProcessObjectList` + `kAudioProcessPropertyIsRunningInput`), match calendar events through EventKit, capture the mic plus the meeting app's audio through a Core Audio process tap, and transcribe each stream separately.

Permalink bases used below:

- Hyprnote / Char, now **Anarlog**: `fastrepl/hyprnote` redirects to `fastrepl/anarlog` ([GitHub API](https://api.github.com/repos/fastrepl/hyprnote)). Pinned at [`7165aba`](https://github.com/fastrepl/anarlog/tree/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9). The app still ships `com.hyprnote.*` bundle IDs ([policy.rs#L32-L37](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/plugins/detect/src/policy.rs#L32-L37)), and the Chrome bridge docs still call it "the Char desktop app" ([chrome-native-host/AGENTS.md](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/chrome-native-host/AGENTS.md)).
- Meetily: [`Zackriya-Solutions/meetily@a2cb62e`](https://github.com/Zackriya-Solutions/meetily/tree/a2cb62e827da7ef59f65064c97233efb2313878e).
- AudioCap: [`insidegui/AudioCap@6f609e8`](https://github.com/insidegui/AudioCap/tree/6f609e8ad1b1e11fa0e8edbe91864cb099f00de3).
- AudioTee: [`makeusabrew/audiotee@56ac954`](https://github.com/makeusabrew/audiotee/tree/56ac954369a09318e46b88a6eec33c2d2b0d32a3).
- Omi desktop (open source, Swift, extra reference): [`BasedHardware/omi@6b7fbc2`](https://github.com/BasedHardware/omi/tree/6b7fbc25dcd434b9dc512a697a163c4330cc558f).
- FluidVoice (open source, Swift, extra reference): [`altic-dev/FluidVoice@6150956`](https://github.com/altic-dev/FluidVoice/tree/6150956bef129fc1a413684db4c0eac61da078a5).

## Summary table

| Product | System-audio capture | Permissions shown | Detection | Auto-stop | Echo handling |
|---|---|---|---|---|---|
| Hyprnote/Anarlog (OSS) | Core Audio **global** mono tap, aggregate device | Mic, System Audio Recording, Calendars, Contacts, Accessibility | Default-input `DeviceIsRunningSomewhere` + per-process `IsRunningInput` poll; calendar ±15 min; Accessibility tree; Chrome extension for Meet | Mic released → 5 s confirm, calendar end + 10 min grace, AX check | Neural AEC (ONNX) on mic with system audio as reference; off when all outputs are headphones |
| Meetily (OSS) | Core Audio global mono tap by default, ScreenCaptureKit backend selectable | Mic, Screen Recording, System Audio | Detector code exists but is not wired to the UI; manual start | Manual | None found; mic + system mixed into one stream |
| Granola | Not documented; asks for Screen & System Audio Recording | Mic, Screen & System Audio Recording, Accessibility (speaker tags) | Calendar + call-app activity | 15 min no audio, call app releases mic, scheduled end, sleep | Not documented |
| Notion AI Meeting Notes | Not documented; needs system audio + screen recording | Mic, system audio, screen recording | Process actively using the mic; calendar ("Join and transcribe" 15 min before) | Manual | Not documented |
| MacWhisper | Not documented; needs Screen Recording | Mic, Screen Recording | Per-app list (Zoom, Teams, browsers, ...); not in App Store build | Manual / "Meeting Ended" notification | Not documented |
| Krisp | Virtual devices "Krisp Microphone" / "Krisp Speaker" | Screen Recording for its screen-record mode | **unverified** | **unverified** | Krisp Speaker gives "echo removal" |
| Jamie | "System audio" (method not documented) | System audio, mic | Mic active + recognized meeting app + calendar window (−5/+10 min) | Mic inactive + final quarter of event + ≥30 s silence; ad-hoc 10 min failsafe | Not documented |
| Superwhisper | Not documented; "records applications on your main display" for modes | Mic, Screen & System Audio Recording, Calendars (optional) | Zoom, Meet, Teams, Slack huddles (app or browser) | Asks before stopping | Not documented |

## Open-source implementations in detail

### Hyprnote / Char / Anarlog

**Capture.**

- System audio is a Core Audio process tap, but **global**, not per-app: `TapDesc::with_mono_global_tap_excluding_processes(&ns::Array::new())`, wrapped in a private aggregate device whose only entry is the tap (`is_private: true`, `tap_auto_start: false`, `tap_list: [tap]`, no main sub-device), with an IO proc on the aggregate device ([speaker/macos.rs#L52-L90](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/audio-actual/src/speaker/macos.rs#L52-L90)). It uses the `cidre` Rust bindings, not raw C.
- The IO proc accepts the tap's native format (F32, F64, I32 or I16) and converts to f32 into a ring buffer ([speaker/macos.rs#L99-L138](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/audio-actual/src/speaker/macos.rs#L99-L138)).
- **Sample-rate drift handling:** every 128 buffers it re-reads the tap ASBD and updates its rate if the output device changed rate ([speaker/macos.rs#L259-L277](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/audio-actual/src/speaker/macos.rs#L259-L277)). Both streams are then resampled to a common rate (`resampled_chunks(sample_rate, chunk_size)`) ([capture/stream.rs#L62-L86](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/audio-actual/src/capture/stream.rs#L62-L86)).
- The mic goes through `cpal`, not AVAudioEngine ([mic.rs](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/audio-actual/src/mic.rs)), and filters its own tap device out of the input list (`name.contains(crate::TAP_DEVICE_NAME)`) ([mic.rs#L18](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/audio-actual/src/mic.rs#L18)).
- Device changes: the source actor restarts the mic on `DefaultInputChanged` and the speaker tap on `DefaultOutputChanged`. It also polls headphone routing and restarts the speaker side when it changes ([listener-core/actors/source/mod.rs#L160-L190](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/listener-core/src/actors/source/mod.rs#L160-L190)).
- With Apple Speech, transcripts are tagged per source: `microphone` → channel 0, `system` → channel 1 ([transcribe-speechanalyzer/src/lib.rs#L175-L193](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/transcribe-speechanalyzer/src/lib.rs#L175-L193)). The `SpeechTranscriber` uses `.volatileResults` and `.audioTimeRange` ([swift-lib/src/lib.swift#L120-L124](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/transcribe-speechanalyzer/swift-lib/src/lib.swift#L120-L124)).

**Permissions.**

- Info.plist declares `NSMicrophoneUsageDescription`, `NSAudioCaptureUsageDescription`, `NSContactsUsageDescription` and `NSCalendarsFullAccessUsageDescription`. It declares **no** `NSScreenCaptureUsageDescription` ([Info.plist](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/apps/desktop/src-tauri/Info.plist)).
- System-audio permission status comes from the private `TCCAccessPreflight("kTCCServiceAudioCapture")` via `dlopen` of TCC.framework, a port of AudioCap ([tcc/swift-lib/src/lib.swift#L1-L27](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/tcc/swift-lib/src/lib.swift#L1-L27)).
- Accessibility is a guided permission ([permissions/src/guidance.rs#L83-L85](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/plugins/permissions/src/guidance.rs#L83-L85)). The meeting-AX detector needs it.

**Meeting detection.**

- **Edge trigger:** a Core Audio listener on `kAudioDevicePropertyDeviceIsRunningSomewhere` of the default input device, plus a listener on `kAudioHardwarePropertyDefaultInputDevice` to re-attach when the default changes. If listener registration fails, it falls back to polling ([mic/macos/mod.rs#L15-L19](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/detect/src/mic/macos/mod.rs#L15-L19), [#L140-L200](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/detect/src/mic/macos/mod.rs#L140-L200)). Edges are debounced over 500 ms ([state.rs#L31](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/detect/src/mic/macos/state.rs#L31)).
- **Who holds the mic:** while the mic is running, it polls every 1 s ([mod.rs#L21](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/detect/src/mic/macos/mod.rs#L21)) over `ca::System::processes()` filtered by `process.is_running_input()`. That is exactly Carbon's planned `ProcessObjectList` + `IsRunningInput` ([list/macos.rs#L84-L109](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/detect/src/list/macos.rs#L84-L109)). Each PID is resolved to its **outermost `.app` bundle** through `NSRunningApplication.bundleURL`, which maps browser and Electron helper processes back to the parent app ([list/macos.rs#L272-L289](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/detect/src/list/macos.rs#L272-L289)). Diffing successive snapshots emits `MicStarted(apps)` and `MicStopped(apps)` ([mic/macos/app.rs](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/detect/src/mic/macos/app.rs)).
- **FaceTime / iPhone calls:** the mic shows up as `avconferenced` / `callservicesd`, which it relabels "FaceTime" or "iPhone Call" depending on which app is running or active ([list/macos.rs#L11-L16](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/detect/src/list/macos.rs#L11-L16), [#L111-L152](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/detect/src/list/macos.rs#L111-L152)).
- **Noise filtering:** an app must hold the mic for **15 s** before a prompt (`DEFAULT_MIC_ACTIVE_THRESHOLD_SECS`). After that, the app gets a **10 min cooldown** ([mic_usage_tracker.rs#L8-L9](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/plugins/detect/src/mic_usage_tracker.rs#L8-L9)). A default ignore list covers dictation apps (Superwhisper, MacWhisper, Wispr Flow, VoiceInk, ...), IDEs, screen recorders, AI assistants and Raycast ([policy.rs#L30-L83](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/plugins/detect/src/policy.rs#L30-L83)).
- **Calendar match:** on detection, it looks up calendar events within **±15 min** of now and uses the first one in the prompt ([detect-events.ts#L434-L438](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/apps/desktop/src/stt/detect-events.ts#L434-L438)).
- **Scheduled auto-start:** there is also a scheduled path. It skips calendar blocks without a meeting link, allows early joins up to 5 min before start, and treats an app that held the mic for ≥10 min before the start as "still on the previous call" ([scheduled-auto-start.tsx#L24-L42](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/apps/desktop/src/stt/scheduled-auto-start.tsx#L24-L42)).

**Auto-stop.**

- On `micStopped` for the trigger app, it schedules a stop after a **5 s** confirm delay. A grace of **10 min** past the calendar end applies, plus network-drop holds of 8 min ([auto-stop.ts#L19-L24](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/apps/desktop/src/stt/auto-stop.ts#L19-L24), [detect-events.ts#L504-L538](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/apps/desktop/src/stt/detect-events.ts#L504-L538)).
- Before stopping, it runs an Accessibility inspection with a 10 s timeout to see whether the call UI is still there ([detect-events.ts#L98-L123](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/apps/desktop/src/stt/detect-events.ts#L98-L123)).
- Sleep events are wired in too ([detect/src/lib.rs](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/detect/src/lib.rs)).

**Browser / Meet tab detection.** Two mechanisms:

1. **Accessibility tree walk** of a recognized browser (Chrome, Edge, Firefox, Safari, Arc, Brave, Dia, Comet, Zen and more) ([meeting_ax/platform.rs#L43-L84](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/detect/src/meeting_ax/platform.rs#L43-L84)):
   - It reads `AXURL` (a CFURL in some browsers, a CFString in others) ([meeting_ax.rs#L2131-L2145](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/detect/src/meeting_ax.rs#L2131-L2145)) and maps the host: `meet.google.com` → Google Meet, `teams.microsoft.com` / `teams.live.com`, `*.zoom.us`, and so on ([platform.rs#L379-L405](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/detect/src/meeting_ax/platform.rs#L379-L405)).
   - It matches window titles of the form `Meet - abc-defg-hij` ([platform.rs#L444-L464](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/detect/src/meeting_ax/platform.rs#L444-L464)).
   - An "active call" needs a visible, enabled `AXButton` labelled `leave call` for Meet (`hang up` for Teams, `leave meeting` for Zoom) ([meeting_ax/node.rs#L95-L160](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/detect/src/meeting_ax/node.rs#L95-L160)).
   - **Labels are English-only.** A French-UI Meet ("Quitter l'appel") would not match **(inference)**.
2. **Chrome extension + Native Messaging host.** The Meet tab's content script sends `{url, is_active, muted, participants[{name, is_self}]}` to a Rust native host. The host writes `chrome_state.json`, and the app polls that file every 500 ms ([chrome-native-host/AGENTS.md](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/chrome-native-host/AGENTS.md), [chrome-native-host/src/main.rs#L1-L40](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/chrome-native-host/src/main.rs#L1-L40)). This is how it gets **participant names** and mute state for Meet. Contacts access is used "to match calendar attendees with names" ([Info.plist](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/apps/desktop/src-tauri/Info.plist)).

**Echo / crosstalk.**

- Mic and system audio go through a **neural AEC**: an ONNX two-stage model in 128/256/512 block sizes, `crates/aec` ([aec/src/lib.rs](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/aec/src/lib.rs), [aec/data/models](https://github.com/fastrepl/anarlog/tree/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/aec/data/models)). The system tap is the far-end reference.
- An `AecReferenceAligner` handles up to **600 ms** of reference lag and a correlation threshold of 0.12. After the neural stage, a residual linear echo-gain canceller runs, with double-talk protection ([capture/stream.rs#L30-L39](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/audio-actual/src/capture/stream.rs#L30-L39), [#L659-L700](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/audio-actual/src/capture/stream.rs#L659-L700)).
- **AEC is disabled when every output device that is playing is a headphone.** The code comment reads: "Headphones make AEC pure cost: it burns CPU and can degrade near-end speech. The check covers every output that is playing, not just the default, because meeting apps pick their own speaker" ([listener-core/actors/source/stream.rs#L48-L76](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/listener-core/src/actors/source/stream.rs#L48-L76), [audio-device/src/lib.rs#L38-L60](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/audio-device/src/lib.rs#L38-L60)).
- Headphone detection works in three ways:
  - Stream terminal type `HEADPHONES` / `HEADSET_MIC` ([audio-device/src/macos.rs#L95-L109](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/audio-device/src/macos.rs#L95-L109)).
  - Name heuristics.
  - **Bluetooth outputs default to "headphone"**, except names on a speaker denylist (HomePod, Sonos, JBL Flip, ...) ([audio-device/src/device.rs#L42-L60](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/audio-device/src/device.rs#L42-L60)).
- A "mic isolated" flag (headphones and the mic not swapped away from the headset) tells downstream code that everything on the mic is the local user ([source/mod.rs#L198-L204](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/listener-core/src/actors/source/mod.rs#L198-L204)).

**Bluetooth / AirPods.**

- `BluetoothInputActivation` "Keeps a Bluetooth headset in HFP/SCO for the life of a capture stream" and restores the previous default input afterwards ([audio-device/src/lib.rs#L267-L300](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/audio-device/src/lib.rs#L267-L300)).
- Default-device change events caused by that handoff are ignored so the capture does not bounce ([source/mod.rs#L206-L215](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/listener-core/src/actors/source/mod.rs#L206-L215)).
- On **Windows only**, it swaps a Bluetooth default mic for a wired one. The reason given: opening a BT headset mic "forces the HFP call profile: the headset gates the mic to silence between words and the wearer's audio drops to 8–16 kHz" ([audio-device/src/lib.rs#L74-L105](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/audio-device/src/lib.rs#L74-L105)).

### Meetily

- **Two backends:**
  - **Core Audio is the macOS default**. It uses the same `with_mono_global_tap_excluding_processes(&[])` global tap + aggregate device, the same `cidre` code lineage as Hyprnote ([capture/backend_config.rs#L77-L84](https://github.com/Zackriya-Solutions/meetily/blob/a2cb62e827da7ef59f65064c97233efb2313878e/frontend/src-tauri/src/audio/capture/backend_config.rs#L77-L84), [capture/core_audio.rs#L85-L120](https://github.com/Zackriya-Solutions/meetily/blob/a2cb62e827da7ef59f65064c97233efb2313878e/frontend/src-tauri/src/audio/capture/core_audio.rs#L85-L120)).
  - **ScreenCaptureKit** is selectable ([backend_config.rs](https://github.com/Zackriya-Solutions/meetily/blob/a2cb62e827da7ef59f65064c97233efb2313878e/frontend/src-tauri/src/audio/capture/backend_config.rs)).
- **Code comments state:**
  - "If permission is denied, the tap will return silence (all zeros)" ([core_audio.rs#L61-L62](https://github.com/Zackriya-Solutions/meetily/blob/a2cb62e827da7ef59f65064c97233efb2313878e/frontend/src-tauri/src/audio/capture/core_audio.rs#L61-L62)).
  - "Including both the tap AND the device creates duplicate audio (echo issue)". That is why its aggregate device holds only the tap ([core_audio.rs#L85-L86](https://github.com/Zackriya-Solutions/meetily/blob/a2cb62e827da7ef59f65064c97233efb2313878e/frontend/src-tauri/src/audio/capture/core_audio.rs#L85-L86)).
- **Permissions:** Info.plist declares Microphone, **Screen Capture** and Audio Capture usage strings ([Info.plist](https://github.com/Zackriya-Solutions/meetily/blob/a2cb62e827da7ef59f65064c97233efb2313878e/frontend/src-tauri/Info.plist)).
- **Detection:** a `SystemAudioDetector` lists processes with `is_running_output()`, meaning audio **output**, not input ([system_detector.rs#L358-L379](https://github.com/Zackriya-Solutions/meetily/blob/a2cb62e827da7ef59f65064c97233efb2313878e/frontend/src-tauri/src/audio/system_detector.rs#L358-L379)). It is exposed as a Tauri command ([system_audio_commands.rs](https://github.com/Zackriya-Solutions/meetily/blob/a2cb62e827da7ef59f65064c97233efb2313878e/frontend/src-tauri/src/audio/system_audio_commands.rs)), but I found no frontend caller (grep of `frontend/src` for `start_system_audio_monitoring` returned nothing). Recording looks manual **(inference)**. No calendar integration was found in the frontend.
- **Echo:** no AEC. Mic and system are **mixed into one stream** with soft clipping before transcription ([pipeline.rs#L158-L201](https://github.com/Zackriya-Solutions/meetily/blob/a2cb62e827da7ef59f65064c97233efb2313878e/frontend/src-tauri/src/audio/pipeline.rs#L158-L201)). Gain is applied after mixing "to prevent amplifying system audio bleed-through in the microphone" ([pipeline.rs#L590-L592](https://github.com/Zackriya-Solutions/meetily/blob/a2cb62e827da7ef59f65064c97233efb2313878e/frontend/src-tauri/src/audio/pipeline.rs#L590-L592)). There is an optional RNNoise path ([pipeline.rs#L285](https://github.com/Zackriya-Solutions/meetily/blob/a2cb62e827da7ef59f65064c97233efb2313878e/frontend/src-tauri/src/audio/pipeline.rs#L285)).
- **Resampling:** a persistent sinc resampler (`SincFixedIn`) to the target rate ([pipeline.rs#L215-L241](https://github.com/Zackriya-Solutions/meetily/blob/a2cb62e827da7ef59f65064c97233efb2313878e/frontend/src-tauri/src/audio/pipeline.rs#L215-L241)).

### AudioCap (insidegui) — reference sample for per-process taps

- **Per-process tap:**
  - Get the process `AudioObjectID` from `kAudioHardwarePropertyProcessObjectList` / `kAudioHardwarePropertyTranslatePIDToProcessObject`.
  - Create `CATapDescription(stereoMixdownOfProcesses: [objectID])` ([ProcessTap.swift#L92](https://github.com/insidegui/AudioCap/blob/6f609e8ad1b1e11fa0e8edbe91864cb099f00de3/AudioCap/ProcessTap/ProcessTap.swift#L92)).
  - Build an aggregate device with the **default system output as `MainSubDevice`**, `IsPrivate: true`, `TapAutoStart: true`, and `kAudioSubTapDriftCompensationKey: true` ([ProcessTap.swift#L110-L131](https://github.com/insidegui/AudioCap/blob/6f609e8ad1b1e11fa0e8edbe91864cb099f00de3/AudioCap/ProcessTap/ProcessTap.swift#L110-L131)).
  - Read `kAudioTapPropertyFormat` into an `AVAudioFormat` ([README](https://github.com/insidegui/AudioCap/blob/6f609e8ad1b1e11fa0e8edbe91864cb099f00de3/README.md)).
- **Permission:**
  - "There's no public API to request audio recording permission or to check if the app has that permission". AudioCap uses the TCC SPI behind a build flag ([README](https://github.com/insidegui/AudioCap/blob/6f609e8ad1b1e11fa0e8edbe91864cb099f00de3/README.md), [AudioRecordingPermission.swift#L40](https://github.com/insidegui/AudioCap/blob/6f609e8ad1b1e11fa0e8edbe91864cb099f00de3/AudioCap/ProcessTap/AudioRecordingPermission.swift#L40)).
  - The `NSAudioCaptureUsageDescription` key "is not listed in the Xcode dropdown, you have to enter it manually" ([README](https://github.com/insidegui/AudioCap/blob/6f609e8ad1b1e11fa0e8edbe91864cb099f00de3/README.md)).

### AudioTee

- Global tap by default, with `--include-processes` / `--exclude-processes` by PID. It "preserves your output device's sample rate" by default and converts with `AVAudioConverter` when `--sample-rate` is passed (output is then Int16). The README warns: "trying to include or exclude a PID which isn't currently playing audio will probably fail to convert to an Audio Object" ([README](https://github.com/makeusabrew/audiotee/blob/56ac954369a09318e46b88a6eec33c2d2b0d32a3/README.md), [AudioFormatConverter.swift](https://github.com/makeusabrew/audiotee/blob/56ac954369a09318e46b88a6eec33c2d2b0d32a3/Sources/AudioTeeCore/Core/AudioFormatConverter.swift)).
- Taps are private ([AudioTapManager.swift#L53](https://github.com/makeusabrew/audiotee/blob/56ac954369a09318e46b88a6eec33c2d2b0d32a3/Sources/AudioTeeCore/Core/AudioTapManager.swift#L53)).

### Omi desktop and FluidVoice (extra open-source Swift references)

- **Omi, system audio:** `CATapDescription(stereoGlobalTapButExcludeProcesses: [])` with `.unmuted`, converted to 16 kHz with `AVAudioConverter` ([SystemAudioCaptureService.swift#L140-L143](https://github.com/BasedHardware/omi/blob/6b7fbc25dcd434b9dc512a697a163c4330cc558f/desktop/macos/Desktop/Sources/SystemAudioCaptureService.swift#L140-L143), [#L296-L315](https://github.com/BasedHardware/omi/blob/6b7fbc25dcd434b9dc512a697a163c4330cc558f/desktop/macos/Desktop/Sources/SystemAudioCaptureService.swift#L296-L315)).
- **Omi, detection findings that matter for Carbon** ([ConferencingApps.swift#L124-L196](https://github.com/BasedHardware/omi/blob/6b7fbc25dcd434b9dc512a697a163c4330cc558f/desktop/macos/Desktop/Sources/ConferencingApps.swift#L124-L196)):
  - "Electron and Chromium-based apps capture the microphone in a helper process with its own bundle ID: a Discord call holds the mic in `com.hnc.Discord.helper.Renderer` (measured 2026-09-26)". Matching is therefore by bundle-ID prefix.
  - "Browsers route call audio through helper processes (e.g. `net.imput.helium.helper`, `com.google.Chrome.helper`)". `com.apple.webkit.gpu` is listed as the "Safari / WebKit media process".
  - "Native call apps keep the mic open even when muted; **a browser drops mic input when muted**, so a muted browser call is detected only via the window-title fallback", which needs Screen Recording permission for window titles.
- **Omi, probe script:** a call-boundary probe logs per-process mic/speaker acquire and release as JSON lines ([call-audio-probe.swift](https://github.com/BasedHardware/omi/blob/6b7fbc25dcd434b9dc512a697a163c4330cc558f/desktop/macos/scripts/call-audio-probe.swift)). It is a good template for Carbon's own measurements.
- **FluidVoice, ownership resolution:** it maps HAL process objects to apps by **executable path inside the owning `.app` bundle**, because "Bundle IDs from HAL are advisory: helpers frequently report their own (or stale) IDs" ([MeetingAutoDetectSignals.swift#L84-L125](https://github.com/altic-dev/FluidVoice/blob/6150956bef129fc1a413684db4c0eac61da078a5/Sources/Fluid/Services/Meeting/MeetingAutoDetectSignals.swift#L84-L125)).
- **FluidVoice, meeting mic:** it enables `setVoiceProcessingEnabled(true)` and sets `voiceProcessingOtherAudioDuckingConfiguration` to `enableAdvancedDucking = false, duckingLevel = .min` ([MeetingMicrophoneCapture.swift#L1006-L1027](https://github.com/altic-dev/FluidVoice/blob/6150956bef129fc1a413684db4c0eac61da078a5/Sources/Fluid/Services/Meeting/MeetingMicrophoneCapture.swift#L1006-L1027)).
- **FluidVoice, VPIO ducking probe:** an integration test measures whether VPIO ducking attenuates what ScreenCaptureKit captures from another app. Its comment says VPIO "was ruled out earlier on the assumption that its system-wide ducking ... would corrupt the recorded `applicationAudio` track — an assumption never measured". It also records that SCStream "delivers buffers of pure zeros" for a windowless helper such as `afplay` ([VoiceProcessingDuckingProbeTests.swift](https://github.com/altic-dev/FluidVoice/blob/6150956bef129fc1a413684db4c0eac61da078a5/Tests/FluidDictationIntegrationTests/VoiceProcessingDuckingProbeTests.swift)). I did not find the measured result.

### BlackHole / Loopback-style virtual drivers

- **BlackHole** is a loopback driver. To hear audio while capturing it, the user must build a **Multi-Output Device** in Audio MIDI Setup and select it as system output ([README](https://github.com/ExistentialAudio/BlackHole/blob/561d934c77a1fa64987e01ccabe890fed30e181f/README.md)). That means manual routing, a driver install and lost per-device volume control, so it is not a fit for a consumer app on macOS 14.2+ **(inference)**.
- **Krisp** takes the same family of approach: the user selects "Krisp Microphone" and "Krisp Speaker" inside the meeting app ([Krisp AI Note Taker](https://krisp.ai/ai-note-taker/)).

## Closed-source products (help-center sources)

### Granola

- **Capture:** "Granola transcribes from your computer's microphone and system audio" ([transcription issues](https://docs.granola.ai/help-center/troubleshooting/transcription-issues)). The device selection "Auto follows your meeting app's microphone when one is open. Otherwise it uses your system default" ([same page](https://docs.granola.ai/help-center/troubleshooting/transcription-issues)). How it learns the meeting app's mic is **unverified**; `kAudioProcessPropertyDevices` would allow it **(inference)**.
- **Permissions:** "Microphone, and Screen & System Audio recording — both must be on" ([transcription issues](https://docs.granola.ai/help-center/troubleshooting/transcription-issues)). Accessibility is needed for speaker tags in Meet (Chrome), Zoom and Teams ([Google Meet speaker tags](https://docs.granola.ai/help-center/taking-notes/speaker-attribution-google-meet), [Zoom speaker tags](https://docs.granola.ai/help-center/taking-notes/speaker-attribution-zoom)). Whether it uses ScreenCaptureKit or a Core Audio tap is **unverified**.
- **Me / Them:** "Green bubbles ... your microphone", "Grey bubbles ... system audio" ([How transcription works](https://docs.granola.ai/help-center/taking-notes/transcription)).
- **Start:** starts only from a notification, a New Note, or an opened upcoming meeting at its scheduled time ([How transcription works](https://docs.granola.ai/help-center/taking-notes/transcription)).
- **Auto-stop:** it stops on:
  - a detected call end (transcript length, call-app activity, scheduled end);
  - "15 minutes passes without any new audio";
  - sleep.

  For ad-hoc meetings, "auto-stop relies on detecting when your call app stops using the microphone". "Your meeting app (e.g. Zoom) may keep the microphone active between calls ... both meetings may be merged into a single transcript" ([How transcription works](https://docs.granola.ai/help-center/taking-notes/transcription), [docs.granola.ai/article/transcription](https://docs.granola.ai/article/transcription)).
- **Bluetooth:** "many Bluetooth headsets can't handle high-quality audio output and microphone input at the same time". The workaround is to pick the built-in mic in Granola ([transcription issues](https://docs.granola.ai/help-center/troubleshooting/transcription-issues)).
- **Participant names:** "use Google Meet's participant names and active-speaker information", read through **Accessibility in Google Chrome** or the **Granola Chrome extension** ([Google Meet speaker tags](https://docs.granola.ai/help-center/taking-notes/speaker-attribution-google-meet)). Zoom names come from the Zoom Workplace desktop app via Accessibility, not the web client ([Zoom speaker tags](https://docs.granola.ai/help-center/taking-notes/speaker-attribution-zoom)).
- **Echo / speakers vs headphones:** not documented on the pages I read.

### Notion AI Meeting Notes

- **Permissions:** "Notion requires access to your system audio and screen recording permissions. This allows us to transcribe other participants' audio when you're using headphones" ([Notion help](https://www.notion.com/help/ai-meeting-notes)). Requires macOS 13+ and desktop app 4.7.0+ ([same](https://www.notion.com/help/ai-meeting-notes)). macOS 13 predates Core Audio taps (14.2), so ScreenCaptureKit is likely, at least as a fallback **(inference)**.
- **Detection:** the app "observes if a user has a process running on their computer that is actively using their microphone (e.g. Zoom)", and "does not listen to the audio coming from your microphone to provide these notifications". The calendar shows "Join and transcribe" starting 15 min before ([Notion help](https://www.notion.com/help/ai-meeting-notes)).
- **Stop:** manual ("select Stop") ([Notion help](https://www.notion.com/help/ai-meeting-notes)).
- **Names:** "If your meeting note is linked to a calendar event, Notion can also label the other participant by name" (best in 1:1). For Meet, "Install the Notion Meetings Add-on browser extension to get speaker labels" ([Notion help](https://www.notion.com/help/ai-meeting-notes)).

### MacWhisper

- **Detection:** "MacWhisper can detect when a meeting starts". The supported list covers Zoom, Teams, Webex, Slack, Discord, WhatsApp, Telegram, Chime, Skype, and the browsers Arc, Brave, Chrome, Edge, Firefox and Safari. "FaceTime is not available due to privacy restrictions built into macOS". The notification auto-dismisses after 10 s ([MacWhisper docs](https://docs.macwhisper.com/article/30-record-meetings)).
- **Permissions:** "requires Screen Recording and Microphone permission". The feature is not in the Mac App Store build ([MacWhisper docs](https://docs.macwhisper.com/article/30-record-meetings)). The likely reason is that it observes other processes **(inference, unverified)**.
- **Stop:** manual, or from the "Meeting Ended Notification". Speakers are "grouped as one speaker" for now ([MacWhisper docs](https://docs.macwhisper.com/article/30-record-meetings)).

### Krisp

- **Capture:** virtual devices. In Zoom, Meet or Teams the user "select[s] Krisp Microphone and Krisp Speaker" ([Krisp AI Note Taker](https://krisp.ai/ai-note-taker/)). A university IT guide adds "select Krisp Speaker (if you want echo removal on your end too)" ([M3USA KB](https://m3usa.teamdynamix.com/TDClient/312/Portal/KB/PrintArticle?ID=22082)). That source is secondary.
- **Bot-free recording:** Krisp's help center describes bot-free recording ([Record your meetings with Krisp AI Note Taker](https://help.krisp.ai/hc/en-us/articles/30146816045980-Record-your-meetings-with-Krisp-AI-Note-Taker)). The page returned HTTP 403 to my fetcher, so its contents are **unverified**.
- **Detection / auto-stop / on-device transcription:** **unverified**.

### Jamie

- **Detection:** "When Jamie detects that you've joined a video call (e.g. Zoom, Google Meet, Microsoft Teams, etc.), a notification will appear". An excluded-apps list exists ([Recorder](https://docs.meetjamie.ai/getting-started/recorder)).
- **Auto-start:** the mic becomes active **and** a calendar event starts "within the next 5 minutes or having started within the last 10 minutes". It "only auto-starts when your microphone is used by an app it recognizes as a meeting app". There is a cancellable countdown. macOS support starts at 5.7.13 ([Auto-start](https://docs.meetjamie.ai/getting-started/auto-start-recording)).
- **Auto-stop:** all three signals must hold at once:
  - the "microphone becomes inactive";
  - the event is "in the final quarter of the calendar event", a signal that stays true after the event ends;
  - "No speech has been detected for at least 30 seconds".

  Without a calendar link, an "inactivity failsafe" waits an extra 5–15 min (default 10). The default mode is "Notification only", which asks instead of stopping ([Auto-stop](https://docs.meetjamie.ai/getting-started/auto-stop-recording)). This is the most complete public stop policy I found.
- **Capture method / echo:** not documented. Jamie says it "records system audio" ([Jamie blog](https://www.meetjamie.ai/en/blog/ai-meeting-note-takers-that-do-not-use-bots-to-join-video-calls)).

### Superwhisper

- **Permissions:** Microphone, "Screen & System Audio Recording ... (Screen Recording on macOS 14)", and Calendars (optional) ([Meetings](https://superwhisper.com/docs/meetings/overview.md)).
- **Detection:** "works with Zoom, Google Meet, Microsoft Teams, and Slack huddles, in the desktop app or the browser". Modes are Off, Notify and Auto. "Either way, Superwhisper asks before it stops a recording" ([Meetings](https://superwhisper.com/docs/meetings/overview.md)).
- **Calendar:** reads macOS Calendar (EventKit). The reminder comes "about a minute before". "The event title and attendees fill in the meeting". It skips all-day, cancelled and declined events, and events with one attendee and no call link ([Meetings](https://superwhisper.com/docs/meetings/overview.md)).
- **Capture scope:** "System audio capture records everything the computer plays, including notification sounds". The dictation-mode system audio "records applications on your main display along with your microphone" ([Microphone & system audio](https://superwhisper.com/docs/common-issues/microphone-and-system-audio.md)). Display-scoped capture suggests ScreenCaptureKit for that path **(inference)**.
- **Bluetooth:** "When a Bluetooth headset's microphone is active, audio quality often drops ... Try selecting your built-in microphone" ([same](https://superwhisper.com/docs/common-issues/microphone-and-system-audio.md)).

## Apple platform facts relevant to Carbon

- **Taps (sample code):**
  - "Use a Core Audio tap to capture outgoing audio from a process or group of processes".
  - "Taps can also mute the process output".
  - "you need to include the `NSAudioCaptureUsageDescription` key".
  - "The first time you start recording from an aggregate device that contains a tap, the system prompts you".

  Source: [Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps).
- **New on macOS 26:**
  - `CATapDescription.bundleIDs`: "An Array of Strings where each String holds the bundle ID of a process to tap or exclude" ([bundleIDs](https://developer.apple.com/documentation/coreaudio/catapdescription/bundleids)).
  - `isProcessRestoreEnabled`: "save tapped processes by bundle ID when they exit, and restore them to the tap when they start up again" ([isProcessRestoreEnabled](https://developer.apple.com/documentation/coreaudio/catapdescription/isprocessrestoreenabled)).
  - Whether `bundleIDs: ["com.google.Chrome"]` also covers `com.google.Chrome.helper*` processes is **unverified**.
  - `isPrivate`: "only visible to the client process that created the tap" ([isPrivate](https://developer.apple.com/documentation/coreaudio/catapdescription/isprivate)).
- **Silent failure:** without the plist key, "TCC denies access silently" and every call returns `noErr`. `AudioDeviceStart` triggers the prompt ([dev.to, "2000 buffers of nothing"](https://dev.to/nickdelv/2000-buffers-of-nothing-3i8)). That source is secondary, but it matches the Meetily comment above.
- **Browser audio processes:** "The process responsible for meeting audio varies depending on the browser and meeting platform" and spans renderer, helper and GPU processes ([Recall.ai, Core Audio taps](https://www.recall.ai/blog/core-audio-taps)). That source is secondary.
- **ScreenCaptureKit alternatives:**
  - `SCStreamConfiguration.excludesCurrentProcessAudio` (macOS 13) ([doc](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/excludescurrentprocessaudio)).
  - `captureMicrophone` (macOS 15) ([doc](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturemicrophone)).
  - SCK needs Screen Recording permission, which is a heavier prompt than audio-only TCC (see Granola, Notion, MacWhisper above).
- **SpeechAnalyzer:**
  - "The analyzer can only analyze one input sequence at a time" ([SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer)). That means **one analyzer per stream**.
  - "the analyzer does not transparently upsample, downsample, or convert audio input". Use `bestAvailableAudioFormat(compatibleWith:)` and convert ([bestAvailableAudioFormat](https://developer.apple.com/documentation/speech/speechanalyzer/bestavailableaudioformat(compatiblewith:))).
  - "Several transcriber instances can share the same backing engine instances and models" ([SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)).
  - `AVAudioConverter` handles rate, bit depth and interleaving ([AVAudioConverter](https://developer.apple.com/documentation/avfaudio/avaudioconverter)).
- **Voice processing (AEC) caveats:**
  - Apple engineer: "when voice processing is enabled, it will duck other audio that is not part of the voice processing output ... if another app is playing audio concurrently, its volume will be significantly reduced. This is intentional". The amount is controllable with `voiceProcessingOtherAudioDuckingConfiguration` ([Apple forums 829753](https://developer.apple.com/forums/thread/829753), [doc](https://developer.apple.com/documentation/avfaudio/avaudioinputnode/voiceprocessingotheraudioduckingconfiguration)).
  - A developer reports that their VPIO-enabled app "cut[s] off the input stream from the other [app]" while recording alongside Zoom. That thread is unanswered, so the claim is **unverified** ([Apple forums 751100](https://developer.apple.com/forums/thread/751100)).
  - Whether macOS VPIO uses other apps' playback as its echo reference (needed to cancel the Zoom/Meet far end) is **unverified**. I found no Apple statement either way.
- **Calendar participants:** `EKCalendarItem.attendees` is "an array of EKParticipant objects", read-only, and nil if there are none. `EKParticipant.name` exists ([attendees](https://developer.apple.com/documentation/eventkit/ekcalendaritem/attendees), [name](https://developer.apple.com/documentation/eventkit/ekparticipant/name)).

## Answers to the specific questions

- **Capture method in the wild:**
  - The open-source desktop apps (Hyprnote, Meetily default, Omi) all use a **global** Core Audio tap, not a per-process one.
  - The closed-source apps (Granola, Notion, MacWhisper, Superwhisper) ask for **Screen & System Audio Recording**, which points to ScreenCaptureKit or a legacy path **(inference)**.
  - Krisp uses a virtual driver.
  - I found **no** shipping product that taps only the meeting app's process. Carbon's plan is the less-trodden path.
- **Detection:** everyone keys off **mic in use**. Notion says it explicitly. Hyprnote's code combines `DeviceIsRunningSomewhere` with per-process `IsRunningInput`. Calendar is the second signal (Jamie: −5/+10 min, Hyprnote: ±15 min, Notion/Superwhisper: reminders). Accessibility is used for in-call UI and names (Hyprnote, Granola). Window titles are used as a fallback (Omi, Hyprnote).
- **Meet tab specifically:** read `AXURL` / window title through Accessibility (`meet.google.com`, `Meet - xxx-xxxx-xxx`) plus the presence of a `leave call` button (Hyprnote). A Chrome extension can also report URL, mute state and participants (Hyprnote, Granola, Notion).
- **Participant names:**
  - The calendar attendee list (Superwhisper, Notion, Hyprnote + Contacts).
  - A browser extension scraping the Meet participant list (Hyprnote, Granola, Notion).
  - The Accessibility tree of Zoom, Teams or Chrome together with active-speaker info (Granola).
- **Auto-stop:** mic released by the trigger app, confirmed by a delay, silence and/or calendar end. Known failure: meeting apps keep the mic between back-to-back calls (Granola). Browsers release the mic when muted (Omi).
- **Echo / crosstalk on speakers:** only Hyprnote documents a real solution in code: reference-based AEC from the system tap, turned off on headphones. Meetily simply mixes the streams. FluidVoice uses VPIO with minimum ducking. No closed-source product documents its approach.
- **Headphones vs speakers:** Hyprnote decides from **all playing outputs** and treats Bluetooth as headphones unless the name looks like a speaker.
- **Bluetooth / AirPods:** opening a BT mic forces HFP (8–16 kHz, call-quality playback). Granola and Superwhisper tell users to choose the built-in mic. Hyprnote pins HFP for the session and ignores the resulting default-device events.
- **Format conversion:** the tap delivers the output device's rate and format (AudioTee README, Hyprnote ASBD probe). Everyone resamples (rubato/sinc in Rust, `AVAudioConverter` in Swift). The rate can change mid-stream when the output device changes.

## Pitfalls checklist for Carbon

- [ ] `NSAudioCaptureUsageDescription` must be in the **compiled** Info.plist (check with `plutil -p`). A missing key or a denial gives **all-zero buffers with `noErr`**. Detect sustained digital silence on the tap and surface a permission hint.
- [ ] There is no public API to preflight audio-capture permission. The prompt fires on the first `AudioDeviceStart` of a tap-backed aggregate device. Trigger it during onboarding, not at the start of the first real Meeting.
- [ ] Browser call audio is rendered by **helper processes** (`com.google.Chrome.helper*`, `com.apple.WebKit.GPU`), not the main PID. A per-PID tap on "Google Chrome" may capture silence. Tap every process object whose executable lives inside the browser bundle, or use macOS 26 `bundleIDs` with the helper IDs listed explicitly. Coverage of helpers by the parent bundle ID is unverified.
- [ ] Re-evaluate the tap's process list while recording. Helpers come and go (Meet can spawn a new renderer), and a PID that is not playing audio may fail to translate to an `AudioObjectID` (AudioTee README). Consider `isProcessRestoreEnabled` on macOS 26.
- [ ] Mic-holder resolution: map PID → outermost `.app` by executable path. Do not trust the HAL bundle ID of helpers. Handle `avconferenced` / `callservicesd` for FaceTime.
- [ ] **A muted browser call releases the mic**, so `IsRunningInput` goes false. Do not auto-stop on mic release alone. Combine it with a confirm delay, silence on the tap stream, calendar end, and/or AX presence of the call UI.
- [ ] Native apps (Zoom, Teams) keep the mic **between back-to-back calls**. Use the calendar boundary to split Meetings.
- [ ] Ignore dictation apps, screen recorders and Carbon itself in detection. Require a minimum hold (Hyprnote uses 15 s) and add a cooldown after dismissal.
- [ ] English-only AX labels ("Leave call") break in French UIs. Prefer the URL / title (`meet.google.com/xxx-xxxx-xxx`) or localized label sets.
- [ ] Echo on speakers: the mic hears the far end, which produces duplicate "Me" text. You need AEC with the **meeting tap as reference**, or at least energy/correlation-based suppression of mic segments that match the tap. Skip it when all playing outputs are headphones.
- [ ] VPIO (`setVoiceProcessingEnabled`) **ducks other apps' audio**, including the meeting app the user is listening to. If used, set `voiceProcessingOtherAudioDuckingConfiguration` to `.min` and test against Zoom and Meet. The report of VPIO cutting another app's input is unverified, but test for it.
- [ ] Opening an AirPods/BT mic forces HFP and degrades what the user hears. Capture the **same input device the meeting app is using** (`kAudioProcessPropertyDevices`, unverified) rather than forcing the default. Expect device-change events during the HFP handoff.
- [ ] The tap's sample rate follows the output device and can change mid-Meeting (AirPods HFP ↔ A2DP, plugging headphones in). Re-read `kAudioTapPropertyFormat`, or listen for rate changes and rebuild the converter.
- [ ] SpeechAnalyzer does not convert formats. Convert each stream to `bestAvailableAudioFormat(compatibleWith:)` with `AVAudioConverter`, and run **one analyzer per stream**.
- [ ] Use a private aggregate device (`IsPrivate`) so it never shows in the user's device lists. Filter it from any input picker anyway, as Hyprnote does.
- [ ] Destroy the aggregate device and tap on stop, on crash recovery and on app quit. Leaked private devices die with the process, but leaked public ones persist **(inference)**.
- [ ] A global tap would also capture notifications and music (Superwhisper doc). A per-process tap avoids this, which is a real advantage of Carbon's plan.
- [ ] Consent: no platform banner appears (ADR-0003). Jamie and Krisp both surface consent tooling. Keep Carbon's ask-before-transcribing flow.

## Recommendation (my opinion)

1. **Keep the Core Audio tap path. It is the right call for an audio-only TCC prompt.** Most closed-source competitors ask for Screen & System Audio Recording. Avoiding that prompt is a real UX differentiator.
2. **Make the tap target "the meeting app's process group", not one PID.** Build the group by walking `kAudioHardwarePropertyProcessObjectList` and selecting every process whose executable path sits inside the detected app's bundle, as FluidVoice does for ownership. Refresh it on `kAudioHardwarePropertyProcessObjectList` changes. On macOS 26, try `bundleIDs` + `isProcessRestoreEnabled` with explicit helper bundle IDs and measure whether it covers Chrome renderers. Keep a **global tap fallback** (excluding Carbon itself) behind a setting for apps where per-process capture comes back silent.
3. **Detection:** adopt Hyprnote's two-level design. An event listener on the default input's `DeviceIsRunningSomewhere` wakes a 1 s per-process `IsRunningInput` poll. Add a 15 s hold, an ignore list, and a calendar window of roughly −5/+15 min. Use EventKit attendees for names in v1. Leave the Accessibility tree and a browser extension for later, because both add a permission or an install.
4. **Auto-stop:** copy Jamie's conjunctive rule. Mic released by the trigger app, **and** silence on both streams for ≥30 s, **and** either the event is in its final quarter or ended, or (ad-hoc) 10 min of inactivity. Ask before stopping by default, as Jamie and Superwhisper do. This survives the muted-browser and back-to-back cases.
5. **Echo:** do not start with VPIO, because of the ducking and multi-app risks. Start with a cheap safeguard. When the output is not headphones, suppress or flag "Me" segments whose text or timing duplicates a "Them" segment, or whose mic energy is explained by the tap signal. Evaluate a reference-based AEC with the per-process tap as reference as the real fix. Hyprnote's alignment plus a neural/linear AEC is the only shipped example. Decide with recorded test calls on MacBook speakers.
6. **Bluetooth:** detect HFP risk (BT output with a BT mic not in use by the meeting app) and capture the meeting app's own input device. Show a one-line tip ("use the built-in mic for better quality") like Granola and Superwhisper do.
7. **Measure before building.** Port Omi's `call-audio-probe.swift` idea into a small debug target. Log per-process input/output and tap levels across Meet (Chrome, Safari), Zoom and Teams, muted and unmuted, on speakers and AirPods. Most of the open questions above are cheap to settle this way.
