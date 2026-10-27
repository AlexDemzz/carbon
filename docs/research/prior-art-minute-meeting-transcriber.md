# Prior art in Minute and meeting-transcriber

Researched 2026-10-27 for [ticket 15](../../.scratch/carbon-v1/issues/15-prior-art-minute-and-meeting-transcriber.md). This note reads the source of two open-source macOS meeting transcribers and asks one question: which of the open Carbon tickets (07, 09, 10, 14) does their shipped code already answer? Each claim links to a file and line range at a pinned commit. Anything I concluded myself, rather than read in their code, is marked **(inference)**. Tap capture is out of scope: [process-tap-findings-verification.md](process-tap-findings-verification.md) already covers pasrom's tap code.

## Sources and pins

| Repo | Pin | License | What it is |
|---|---|---|---|
| [roblibob/minute](https://github.com/roblibob/minute/tree/97b5cd0d328090b35ebf6182062a9db39a459513) ("Minute") | `97b5cd0` | MIT | SwiftUI app. Mic + ScreenCaptureKit system audio mixed to one track; post-meeting whisper.cpp or Parakeet, FluidAudio offline diarization, local LLM summary into an Obsidian-style vault. |
| [pasrom/meeting-transcriber](https://github.com/pasrom/meeting-transcriber/tree/1765408a99b4c1360735648df7f41055e647f4a5) ("pasrom") | `1765408` (same pin as the tap note) | MIT | Menu-bar app. Auto-detects Teams/Zoom/Webex/browser calls, records app and mic as separate tracks, post-meeting WhisperKit or Parakeet per track, dual-track FluidAudio diarization, voice memory, summary via Claude CLI or an OpenAI-compatible endpoint. |

Both pin FluidAudio, which is Carbon's planned dependency: Minute at revision `e5c6456` ([Package.swift#L35](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Package.swift#L35)), pasrom `from: "0.15.5"`, resolved to `21493f8` ([Package.swift#L16](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Package.swift#L16)).

Link prefixes used below:
- **M** = `https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/`
- **P** = `https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/`

## Summary

| Topic | Minute | pasrom | Carbon's current design |
|---|---|---|---|
| Start signal | Default input device "running somewhere" ≥ 0.35 s → a **notification asking** to record. No per-process attribution, no ignore list. | **IOKit power assertions** per app (Teams "call in progress", Zoom display-sleep type, browser "WebRTC has active PeerConnections"). 2 polls × 3 s to confirm. Mic-in-use only for WeChat/FaceTime/WhatsApp/Tencent, off by default. | Mic held > 15 s by a non-ignored process, plus EventKit. |
| Stop signal | Combined mic + system level below a threshold for 120 s → 30 s "Keep recording" countdown. | The start signal disappears for 15 s (end grace). 4 h cap. No silence rule, no calendar. | Mic released + 30 s silence + event ended; no event → mic released + 10 min silence. |
| ASR | whisper.cpp (default) or Parakeet v3, post-meeting, on the mixed track | WhisperKit large-v3-turbo (default) or Parakeet TDT v3, post-meeting, **per track**; live captions are an opt-in PoC | SpeechTranscriber live, Parakeet post-pass as a candidate |
| Silence guard | None. Whisper's no-speech gating is turned **off** | Optional FluidAudio VAD trim (off by default, threshold 0.5); WhisperKit drops consecutive duplicate segments | Open (ticket 14, Q3) |
| Diarization | FluidAudio offline (VBx) on the mix, clustering threshold 0.8 | FluidAudio offline on the app and mic tracks separately (threshold 0.6), Sortformer optional; mic = "Me" | FluidAudio offline on "Them", mic = "Me" |
| Word ↔ speaker merge | Segment-level max overlap | Segment-level max overlap + nearest-gap fallback | Word-level (`audioTimeRange`), open |
| Voice memory | Cosine **similarity ≥ 0.70**, up to 20 embeddings per person, suggestion only | Cosine **distance < 0.40 and ≥ 0.10 margin** over the runner-up; centroid + 3 recent samples | FluidAudio bands (< 0.5 / 0.5–0.7 / ≥ 0.7), unverified |
| Summary | Local llama.cpp, Gemma 3 4B Q4 default. Rolling chunk → JSON delta → deterministic merge | Whole transcript to Claude CLI / OpenAI-compatible endpoint, no chunking | Foundation Models, chunked to 4K |
| Reusable tests | Silence auto-stop unit tests, a multi-pass summary fixture | **DER/WER harness, AMI excerpt (CC BY 4.0), synthetic `say` fixtures, blessed baseline**, Jitsi WebRTC e2e | Not yet |

Neither app uses SpeechTranscriber, Foundation Models or EventKit. Their code therefore answers *how* questions (rules, thresholds, merge algorithms, harnesses), not *how well Apple's engines do* questions.

## 1. Detection and auto-stop (ticket 09)

### pasrom: power assertions, not the mic

- **Why not the mic.** The production detector is `PowerAssertionDetector`, which reads `IOPMCopyAssertionsByProcess()`: "sandbox-safe, no entitlement needed" ([P PowerAssertionDetector.swift#L7-L11](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/PowerAssertionDetector.swift#L7-L11)). The window-title detector is explicitly "Not the production detector" ([P MeetingDetector.swift#L9-L13](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/MeetingDetector.swift#L9-L13)).
- **Per-app rules, with field measurements** ([P PowerAssertionDetector.swift#L119-L166](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/PowerAssertionDetector.swift#L119-L166)):
  - **Teams:** processes `MSTeams`, `Microsoft Teams`, `Microsoft Teams WebView`, `Microsoft Teams (work or school)`; keyword `call in progress` only. The type is deliberately not matched, because "Teams, whose WebView holds a display-sleep 'Video Wake Lock' even with no call in progress, so it must stay keyword-only" ([#L19-L26](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/PowerAssertionDetector.swift#L19-L26); test [P PowerAssertionDetectorTests.swift#L84-L95](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Tests/PowerAssertionDetectorTests.swift#L84-L95)).
  - **Zoom:** process `zoom.us`; keyword `zoom` **or** assertion type `PreventUserIdleDisplaySleep` / `NoDisplaySleepAssertion`. Newer Zoom names its in-call assertion "Describe Activity Type" (Apple's sample placeholder), measured on macOS 26 (issue #446; [P PowerAssertionDetectorTests.swift#L111-L128](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Tests/PowerAssertionDetectorTests.swift#L111-L128)). A Zoom *system*-sleep assertion does not count ([#L130-L135](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Tests/PowerAssertionDetectorTests.swift#L130-L135)).
  - **Webex:** keywords `webex`, `on a call`. Measured: during a call the client holds "On a call" (`PreventUserIdleDisplaySleep`), and an idle client holds no assertion at all ([P PowerAssertionDetectorPatternsTests.swift#L290-L302](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Tests/PowerAssertionDetectorPatternsTests.swift#L290-L302), [#L379-L382](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Tests/PowerAssertionDetectorPatternsTests.swift#L379-L382)).
  - **Browsers (Meet, web Zoom/Teams, Whereby):** any process holding an assertion named with `webrtc` / `peerconnection` ("WebRTC has active PeerConnections", which lives in Chromium's content layer). Assertion types are not matched, because Chromium holds the same type for YouTube. Native clients are excluded from this rule. Because any WebRTC use fires it, browser hits **ask for consent** instead of auto-recording ([P MeetingPatterns.swift#L101-L120](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/MeetingPatterns.swift#L101-L120), [P PowerAssertionDetector.swift#L416-L467](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/PowerAssertionDetector.swift#L416-L467)). The code says nothing about Safari: WebKit is not Chromium, so this keyword may not fire there **(inference)**.
- **Mic-in-use as a fallback channel.** `MicInputDetector` uses the same API Carbon plans (`kAudioHardwarePropertyProcessObjectList` + `kAudioProcessPropertyIsRunningInput`), but only for WeChat, Tencent Meeting, FaceTime and WhatsApp, all off by default. Its header states the cost: "a WeChat or WhatsApp voice message longer than roughly … 6 s … looks like a call. There is no minimum-duration filter downstream" ([P MicInputDetector.swift#L7-L26](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/MicInputDetector.swift#L7-L26)). Measured on macOS 26.5.2: during a FaceTime audio call, input is reported by `com.apple.avconferenced`, "and `com.apple.FaceTime` never reports input at all" ([#L66-L78](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/MicInputDetector.swift#L66-L78)). Bundles that hold the mic without matching any pattern are logged once each, as a discovery channel ([#L211-L220](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/MicInputDetector.swift#L211-L220)).
- **Thresholds:**
  - Poll every 3 s; a hit must repeat on 2 consecutive polls ([P WatchLoop.swift#L120-L122](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/WatchLoop.swift#L120-L122), [P PowerAssertionDetector.swift#L218-L223](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/PowerAssertionDetector.swift#L218-L223)).
  - **End grace of 15 s:** the recording stops once the assertion has been absent for 15 s straight. Any reappearance resets the grace ([P WatchLoopEndPolicy.swift#L42-L62](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/WatchLoopEndPolicy.swift#L42-L62)).
  - Max duration 4 h (14 400 s). Users can change the poll and grace values, with a 1 s floor ([P AppSettings.swift#L183-L195](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/AppSettings.swift#L183-L195), defaults [#L593-L594](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/AppSettings.swift#L593-L594)).
- **Back-to-back calls.** After a recording ends, the loop calls `reset`, which puts that app in a **5 s cooldown** and then resumes polling. The next call is a new Meeting as soon as its assertion is seen again ([P WatchLoop.swift#L383-L410](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/WatchLoop.swift#L383-L410), [P PowerAssertionDetector.swift#L374-L379](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/PowerAssertionDetector.swift#L374-L379)). This only splits two calls if Zoom drops its display-sleep assertion between them for at least 15 s. pasrom does not say whether it measured that **(inference)**.
- **Muting** plays no part in pasrom's start or stop decisions. Its health checks treat mic silence as healthy: "a microphone whose owner is listening rather than talking is quiet, not broken" ([P README.md#L230](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/README.md#L230)).
- **Titles.** Teams idle-tab titles (`Chat |`, `Calendar |` …) are filtered out so they are never used as the Meeting title ([P MeetingPatterns.swift#L38-L58](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/MeetingPatterns.swift#L38-L58)). This is relevant only if Carbon falls back to window titles when no calendar event matches.

### Minute: device-level mic prompt and a silence countdown

- **Start:**
  - It listens for `kAudioDevicePropertyDeviceIsRunningSomewhere` on the **default input device** and fires when the device has been running for ≥ 0.35 s ([M MicrophoneActivityMonitor.swift#L5-L11](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Services/MicrophoneActivityMonitor.swift#L5-L11), [#L186-L209](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Services/MicrophoneActivityMonitor.swift#L186-L209)).
  - The result is a "Microphone active … Start recording this meeting?" notification, at most once every 30 s, and only while the pipeline is idle ([M MicActivityNotificationCoordinator.swift#L13](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Services/MicActivityNotificationCoordinator.swift#L13), [#L54-L74](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Services/MicActivityNotificationCoordinator.swift#L54-L74)).
  - Because the signal is device-level, Minute cannot tell a dictation app from Zoom, so it has no ignore list. Carbon's per-process approach is strictly more informative **(inference)**.
- **Stop:**
  - `SilenceDetectionPolicy` defaults: 120 s of silence, a 30 s warning countdown, an RMS threshold of 0.03, and 0.75 s of transient tolerance ([M SilenceDetection.swift#L9-L19](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Domain/SilenceDetection.swift#L9-L19)).
  - Non-silent bursts shorter than 0.75 s do not reset the silence count. Speech during the countdown cancels it, and so does "Keep recording" ([M SilenceAutoStopController.swift#L59-L94](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Services/SilenceAutoStopController.swift#L59-L94), [#L118-L164](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Services/SilenceAutoStopController.swift#L118-L164)).
  - The level fed in is `min(micLevel + systemLevel, 1)`, where each level is `peakRMS × 4` ([M DefaultAudioService.swift#L243-L261](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Services/DefaultAudioService.swift#L243-L261), [#L394-L405](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Services/DefaultAudioService.swift#L394-L405); fed at [M MeetingPipelineViewModel.swift#L2172-L2186](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/Minute/Sources/ViewModels/MeetingPipelineViewModel.swift#L2172-L2186)). The threshold is therefore a raw RMS of 0.0075, about −42 dBFS on the summed channels **(inference, arithmetic)**.
  - Because both channels are summed, a muted local user does not count as silence while the far end is talking.

### What this means for Carbon (inference)

- **Zoom and Teams: power assertions would settle the disagreement.** Ticket 09 lists Zoom holding the mic between back-to-back calls, and Teams holding it while idle (the sources disagree in [native-meeting-app-audio-processes.md](native-meeting-app-audio-processes.md)). pasrom never depends on who holds the mic for these apps: it starts and stops on the in-call power assertion. Adding that as a second signal next to mic-in-use costs one IOKit call per poll and no entitlement. It gives Carbon an "in a call" bit for Zoom, Teams and Webex whatever the mic does. This is a design change to the Detection rules in [ticket 01](../../.scratch/carbon-v1/issues/01-carbon-v1-product-design.md), so it is only proposed here.
- **Browsers: a confirmation, not a trigger.** The WebRTC assertion fires for any WebRTC page, so pasrom asks before recording. For Carbon, which already pairs mic-in-use with calendar events, the assertion could confirm a browser Meeting rather than start one.
- **Starting values for the thresholds:**
  - pasrom confirms a call in ~6 s and stops after 15 s of grace. Minute stops after 120 s + 30 s of silence.
  - Carbon's 15 s start and 30 s stop are inside that range. Its 10 min no-event stop is far more conservative than either app.
  - Neither app has a calendar-end condition to compare against.
- **Ignored apps.** Neither app ships an ignore list, because neither starts on generic mic use. pasrom's "log unmatched mic holders once" diagnostic is a cheap way to build Carbon's list from real usage.

## 2. Diarization and Voice Print (ticket 07)

### Engines and settings

- **Minute** runs FluidAudio `OfflineDiarizerManager` on the **mixed** mic + system file, with `clusteringThreshold: 0.8` ([M FluidAudioOfflineDiarizationService.swift#L31-L39](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Services/FluidAudioOfflineDiarizationService.swift#L31-L39), [#L66-L80](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Services/FluidAudioOfflineDiarizationService.swift#L66-L80); the mix comes from [M DefaultAudioService.swift#L218](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Services/DefaultAudioService.swift#L218) and is diarized at [M MeetingPipelineCoordinator.swift#L276-L298](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Pipeline/MeetingPipelineCoordinator.swift#L276-L298)).
- **pasrom** runs offline diarization by default, with Sortformer as an option ([P AppSettings.swift#L620-L631](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/AppSettings.swift#L620-L631)).
  - It keeps FluidAudio's defaults: Euclidean cluster threshold 0.6, VBx warm start Fa 0.07 / Fb 0.8, embeddings only for segments ≥ 1.0 s, overlap excluded from embeddings ([P AppSettings.swift#L389-L421](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/AppSettings.swift#L389-L421)).
  - The app and mic tracks are diarized **separately**, with speaker IDs prefixed `R_` and `M_` ([P DiarizationProcess.swift#L158-L160](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/DiarizationProcess.swift#L158-L160)).
  - The mic is labelled "Me" unless the user clears the name to diarize a room ([P AppSettings.swift#L270-L274](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/AppSettings.swift#L270-L274)). That matches Carbon's "Me" / "Them" split.
- The two apps' clustering thresholds differ (0.8 vs 0.6), and neither documents how its value was chosen. Carbon should treat this knob as something to measure, not copy.

### Merging speakers with transcript timings

- **Both merge at segment level, not word level.** Each ASR segment takes the speaker whose diarization segment overlaps it the most:
  - Minute falls back to the previous speaker, returns no attribution at all if nothing overlapped, and merges adjacent same-speaker segments ([M SpeakerAttribution.swift#L4-L44](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Utilities/SpeakerAttribution.swift#L4-L44)).
  - pasrom falls back to the nearest diarization segment by gap, then "UNKNOWN" ([P DiarizationProcess.swift#L87-L133](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/DiarizationProcess.swift#L87-L133)). It joins same-speaker blocks unless the pause is > 2.0 s ([#L240-L247](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/DiarizationProcess.swift#L240-L247)).
- **How segments are cut** sets how coarse that merge is:
  - Minute cuts Parakeet tokens at a ≥ 1.0 s gap, 8 s maximum, or `. ? !` ([M FluidAudioTranscriptionService.swift#L189-L238](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Services/FluidAudioTranscriptionService.swift#L189-L238)).
  - pasrom cuts at `. ! ?` or a soft cap of 20 tokens at a word boundary ([P ParakeetTokenGrouping.swift#L8-L48](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/ParakeetTokenGrouping.swift#L8-L48)).
  - A whole sentence goes to one speaker. Carbon's word-level plan in [on-device-diarization.md](on-device-diarization.md) is finer than both, and neither app tells us whether word-level is worth it.
- **Echo.** pasrom marks mic segments as `.echoOnly` when the app track's acoustics explain them, so loudspeaker bleed is not attributed to "Me". The decision is made on audio, never on text, because "a far end replaying what you just said produces exactly the same pair of lines" ([P EchoSegmentClassifier.swift#L18-L30](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/EchoSegmentClassifier.swift#L18-L30)). It is off by default ([P AppSettings.swift#L623-L624](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/AppSettings.swift#L623-L624)). This covers a gap in ticket 06's "speakers" (no headphones) Meetings.

### Cross-meeting matching thresholds

- **Minute:**
  - Embeddings are 256-dim, aggregated per cluster as an L2-normalized mean ([M OfflineDiarizerEmbeddingExport.swift#L59-L108](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Utilities/OfflineDiarizerEmbeddingExport.swift#L59-L108)).
  - A match needs **cosine similarity ≥ 0.70** against the best stored embedding of a profile ("intentionally conservative … err on the side of no suggestion"). Profiles are filtered by embedding-model version ([M SpeakerEmbeddingMatcher.swift#L20-L77](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Utilities/SpeakerEmbeddingMatcher.swift#L20-L77)).
  - Each profile keeps at most 20 embeddings, FIFO ([M SpeakerProfileStore.swift#L70](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Services/SpeakerProfileStore.swift#L70), [#L123-L124](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Services/SpeakerProfileStore.swift#L123-L124)).
- **pasrom:**
  - A label is auto-named only if its best candidate has **cosine distance < 0.40** and beats the runner-up by **≥ 0.10**. Each stored name is used once per Meeting ([P SpeakerMatcher.swift#L31](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/SpeakerMatcher.swift#L31), [#L98-L147](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/SpeakerMatcher.swift#L98-L147)).
  - The distance is the minimum over the person's running-mean centroid and their last 3 samples ([P RecognitionStats.swift#L91-L95](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/RecognitionStats.swift#L91-L95)).
  - Only embeddings from ≥ 3 s of speech update the centroid ([P SpeakerMatcher.swift#L14-L20](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/SpeakerMatcher.swift#L14-L20), [#L236-L274](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/SpeakerMatcher.swift#L236-L274)).
  - **Participant pre-match:** when the number of unnamed labels equals the number of unused participant names (read from the Teams window), labels sorted by speaking time get those names ([#L468-L500](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/SpeakerMatcher.swift#L468-L500)). That is crude: it assigns names arbitrarily but deterministically. EventKit attendees would be Carbon's equivalent input **(inference)**.
- **Both apps are stricter than FluidAudio's documented bands.** As a distance, Minute's threshold is ≤ 0.30, against FluidAudio's < 0.5 "same" and 0.65 default. A starting point for Carbon (opinion): auto-match below ~0.35–0.40 distance with a margin over the runner-up, ask up to ~0.5–0.6, otherwise a new Speaker. Measure it, as ticket 07 already says.

### Published numbers

pasrom's blessed CI baseline ([P quality-baseline.json](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Tests/Fixtures/quality/quality-baseline.json)), DER without a collar:

| Fixture | Offline (VBx) | Sortformer |
|---|---|---|
| `four_speakers_en_ami` (94 s of a real AMI meeting) | 0.361 | 0.329 |
| `three_speakers_de` (synthetic `say` voices) | 0.681 | 0.109 |
| `two_speakers_de` (synthetic) | 0.526 | 0.060 |

These are regression gates on clips of a minute or two, not benchmarks. They are far worse than FluidAudio's 10.6 % on full AMI meetings (offline needs long audio to cluster well) **(inference)**. They do suggest that Sortformer deserves a slot in ticket 07's comparison for short calls with 2–4 people, which [on-device-diarization.md](on-device-diarization.md) set aside on full-AMI DER.

## 3. Transcription engine and silence (ticket 14)

- **Neither app runs SpeechTranscriber; both transcribe after the Meeting.**
  - pasrom defaults to WhisperKit `openai_whisper-large-v3-v20240930_turbo`, with language `de` by default, and offers Parakeet TDT v3 ([P AppSettings.swift#L607-L612](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/AppSettings.swift#L607-L612)). Live transcription is an opt-in PoC, captions only ([#L231-L238](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/AppSettings.swift#L231-L238)).
  - Minute defaults to whisper.cpp, with Parakeet v3 as an option ([M TranscriptionBackend.swift#L27-L31](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Domain/TranscriptionBackend.swift#L27-L31), [M FluidAudioModels.swift#L18](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Domain/FluidAudioModels.swift#L18)).
- **Parakeet language hint.** pasrom passes an optional ISO 639-1 hint to FluidAudio. Its comment notes that without one, "FluidAudio's v3 TDT decoder picks the script freely, which can drift Cyrillic ↔ Latin on multi-script audio" ([P ParakeetEngine.swift#L44-L56](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/ParakeetEngine.swift#L44-L56)). Carbon can pass the Meeting Language as that hint, so ticket 14's Q2 (does auto-detection slip?) becomes a fallback question, not a blocker **(inference)**.
- **Silence guards:**
  - pasrom can trim non-speech with FluidAudio's VAD before ASR and remap the timestamps afterwards. It is **off by default**, with threshold 0.5, a 0.3 s merge gap and a 0.15 s minimum region ([P AppSettings.swift#L621-L622](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/AppSettings.swift#L621-L622), [P FluidVAD.swift#L101-L110](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/FluidVAD.swift#L101-L110), [P PipelineQueue+Stages.swift#L1081-L1099](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/PipelineQueue%2BStages.swift#L1081-L1099)).
  - For WhisperKit, pasrom drops a segment whose text repeats the previous one ([P WhisperKitEngine.swift#L342-L354](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/WhisperKitEngine.swift#L342-L354)).
  - Minute does the opposite: `no_speech_thold = 1.0`, `logprob_thold = -1.0`, `suppress_blank = false`, `suppress_nst = false`, "to bias towards returning *something*" ([M WhisperLibraryTranscriptionService.swift#L115-L124](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Services/WhisperLibraryTranscriptionService.swift#L115-L124)). For Parakeet it only logs input with RMS < 0.001 as near-silent ([M FluidAudioTranscriptionService.swift#L74-L76](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Services/FluidAudioTranscriptionService.swift#L74-L76)).
  - Neither codebase measures phantom text on muted stretches, so Q3 stays open.
- **Proper nouns (Q9).** Both ship Parakeet CTC vocabulary boosting: Minute in [M VocabularyBoosting.swift](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Domain/VocabularyBoosting.swift), pasrom in [P ParakeetVocabularyConfiguration.swift](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/ParakeetVocabularyConfiguration.swift), from one shared vocabulary file ([P README.md#L89](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/README.md#L89)). The integration path is proven in shipping apps. Its effect is not measured in either.
- **WER baseline** (pasrom, same quality-baseline file as the DER table):

  | Fixture | Parakeet v3 | WhisperKit large-v3-turbo |
  |---|---|---|
  | `four_speakers_en_ami` (real, 94 s) | 0.374 | 0.290 |
  | `three_speakers_de` (synthetic) | 0.453 | 0.264 |
  | `two_speakers_de` (synthetic) | 0.429 | 0.286 |

  On these clips Parakeet loses to Whisper turbo. That runs against the FLEURS / Earnings-22 comparisons cited in [speechtranscriber-vs-whisper-cpp.md](speechtranscriber-vs-whisper-cpp.md). The clips are tiny, the AMI one is far-field headset-mix speech with heavy overlap, and the WER tokenizer does no number or filler normalization ([P WERCalculator.swift#L3-L22](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Tests/Quality/WERCalculator.swift#L3-L22)). Treat it as a warning that Parakeet's advantage is not a given on meeting audio, not as a verdict **(inference)**.

## 4. Summary (ticket 10)

- **Neither app uses Foundation Models.**
  - Minute defaults to Gemma 3 4B IT Q4_K_M through llama.cpp, with 27B, Ollama and LM Studio as options ([M SummarizationModels.swift#L53-L61](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Domain/SummarizationModels.swift#L53-L61)).
  - pasrom sends the whole transcript, unchunked, to Claude CLI or an OpenAI-compatible endpoint, caps output tokens, and reports a truncated result instead of showing it as complete ([P OpenAIProtocolGenerator.swift#L23-L35](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/OpenAIProtocolGenerator.swift#L23-L35)). So pasrom has nothing to offer on chunking.
- **Minute's chunk-then-merge is the design ticket 10 needs, already built and tested:**
  - **Budget:** input per pass = context − 1 024 output − 256 margin − 512 prompt overhead. Tokens are estimated at 4 UTF-8 bytes per token ([M SummarizationPassPlanner.swift#L3-L24](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Services/SummarizationPassPlanner.swift#L3-L24), [#L55-L88](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Services/SummarizationPassPlanner.swift#L55-L88), [#L133-L136](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Services/SummarizationPassPlanner.swift#L133-L136)).
  - **Chunking:** chunks break only between lines, and a single oversized line becomes its own chunk ([#L90-L131](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Services/SummarizationPassPlanner.swift#L90-L131)).
  - **Rolling passes:** each pass gets the "existing accepted state" JSON and must "Return only net-new material from this transcript chunk", with fields `summary_points`, `decisions`, `action_items`, `open_questions`, `key_points` ([M LlamaLibrarySummarizationService.swift#L432-L470](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteLlama/Services/LlamaLibrarySummarizationService.swift#L432-L470); loop at [M MeetingPipelineCoordinator.swift#L527-L569](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Pipeline/MeetingPipelineCoordinator.swift#L527-L569)).
  - **Merge:** the model never rewrites the whole summary. Code merges the deltas, deduplicating items whose normalized text contains the other's and keeping the longer one ([M SummarizationSummaryMerger.swift#L6-L24](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Services/SummarizationSummaryMerger.swift#L6-L24), [#L71-L141](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Services/SummarizationSummaryMerger.swift#L71-L141)). Invalid JSON gets one repair attempt ([M MeetingPipelineCoordinator.swift#L803-L810](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Pipeline/MeetingPipelineCoordinator.swift#L803-L810)).
  - **4K is their floor.** The 4K preset is labelled "Debug-only minimum context window for reproducing constrained-memory summarization behavior". 8K is recommended for 8 GB Macs ([M SummarizationContextWindowPreset.swift#L52-L80](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Domain/SummarizationContextWindowPreset.swift#L52-L80)).
- **Applied to Foundation Models (inference):**
  - With a 4 096-token context, Minute's budget leaves 2 304 input tokens per pass, about 9 KB of transcript.
  - A one-hour Meeting (roughly 9–10k spoken words, ~50–60 KB with speaker labels) would take about 6 passes.
  - Each pass after the first also carries the growing state JSON, so the real budget shrinks pass by pass. The 1 024-token output reserve may be too generous for a delta.
  - Ticket 10's time-per-hour measurement should count passes, not just one call.
- **Prompt rules worth copying:** each meeting-type strategy says "No Hallucinations: If a field has no content, return an empty array []. Do not invent tasks to fill space" ([M GeneralPromptStrategy.swift#L49](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Sources/MinuteCore/Summarization/Prompts/Strategies/GeneralPromptStrategy.swift#L49)).

## 5. Reusable tests, fixtures and eval code

Both repos are MIT, so code can be reused with the copyright notice kept. Fixture audio has its own licence.

- **pasrom quality harness**, the most useful find:
  - [DERCalculator.swift](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Tests/Quality/DERCalculator.swift#L3-L28): NIST-style overlap-aware DER, brute-force speaker mapping, no collar.
  - [WERCalculator.swift](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Tests/Quality/WERCalculator.swift#L3-L22): Levenshtein WER, Unicode lowercase, Latin punctuation stripped.
  - Ground-truth JSON format ([GroundTruth.swift](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Tests/Quality/GroundTruth.swift)), a baseline gate ([QualityBaselineGate.swift](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Tests/Quality/QualityBaselineGate.swift)) and a bless script ([bless_quality_baseline.sh](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/scripts/bless_quality_baseline.sh)).
  - This is exactly the scoring code tickets 07 and 14 need. Carbon would add a French normalizer (elisions, numbers) **(inference)**.
- **Fixtures:**
  - `four_speakers_en_ami.wav`: AMI ES2004a Mix-Headset, 948.0–1041.8 s, 16 kHz, **CC BY 4.0**, truth built from the AMI manual annotations. The generator re-downloads the source and checks a SHA-256 ([ATTRIBUTION.md](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Tests/Fixtures/quality/ATTRIBUTION.md), [ami_fixture_truth.py#L1-L30](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/scripts/lib/ami_fixture_truth.py#L1-L30), [generate_real_meeting_fixture.sh](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/scripts/generate_real_meeting_fixture.sh)). This feeds [ticket 16](../../.scratch/carbon-v1/issues/16-public-meeting-corpora.md).
  - Synthetic multi-speaker fixtures from macOS `say` voices ([generate_quality_fixtures.sh](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/scripts/generate_quality_fixtures.sh)). They are German, but the script takes voice/text lines, so a French set with French system voices is a small change **(inference)**. `two_speakers_de_with_silence.wav` ([generate_test_audio_with_silence.sh](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/scripts/generate_test_audio_with_silence.sh)) is a ready silence-gap case.
  - [make-echo-pair.py](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/scripts/fixtures/make-echo-pair.py) synthesizes a dual-track app/mic pair with loudspeaker bleed.
- **pasrom e2e with a real WebRTC call, no account:**
  - [jitsi-keeper.mjs](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/scripts/fixtures/jitsi-keeper.mjs#L1-L14) joins one public Jitsi room from two Chrome tabs through a real SFU. Each tab's `getUserMedia` is replaced by a WebAudio stream, so server-transported meeting audio plays out of Chrome.
  - [e2e-browser.sh](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/scripts/e2e-browser.sh) drives detection and capture end to end.
  - Swapping the 440 Hz tone for a corpus file would give "corpus audio through a real call" with Opus compression and no human participants. That is the experiment ticket 16 asks about **(inference)**.
- **pasrom detection fixtures:** `PowerAssertionFixture` plus tests that carry **measured** assertion dumps (Teams Video Wake Lock, Zoom "Describe Activity Type", Webex "On a call", Amphetamine) ([PowerAssertionDetectorPatternsTests.swift#L290-L400](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Tests/PowerAssertionDetectorPatternsTests.swift#L290-L400)).
- **Minute:**
  - [SilenceAutoStopControllerTests.swift](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Tests/MinuteCoreTests/SilenceAutoStopControllerTests.swift) is a pattern for clock-injected auto-stop tests.
  - [long_multipass_fixture.md](https://github.com/roblibob/minute/blob/97b5cd0d328090b35ebf6182062a9db39a459513/MinuteCore/Tests/MinuteCoreTests/Fixtures/Transcript/long_multipass_fixture.md) is a synthetic repeated-line transcript that forces multi-pass planning. It tests mechanics only, not quality.
  - No audio fixtures.
- **Nothing in either repo is French, and nothing is real VoIP-compressed two-track audio with a reference.** The hand-recorded set in ticket 06 is still needed for those properties.

## Answers for the open tickets

### Diarization and Voice Print quality on real calls (07)

- **Already answered by shipped code:**
  - Engine: FluidAudio offline, as planned.
  - Diarize the app track separately and label the mic "Me": pasrom does exactly this.
  - A baseline merge rule: segment-level max overlap with a nearest-gap fallback, and a new block after a 2 s pause.
  - Voice Print bookkeeping: centroid plus a few recent samples, ≥ 3 s speech to update the centroid, model-version tag, one name per Meeting.
  - Starting thresholds: auto-match at distance < 0.40 with a 0.10 margin (pasrom), similarity ≥ 0.70 (Minute).
  - Scoring code (DER) and an AMI clip.
- **Left for a hand-run check:**
  - DER on French and English VoIP "Them" tracks.
  - The actual distance bands on tap audio.
  - Whether word-level splitting beats segment-level at turn boundaries.
  - Offline vs Sortformer on short 2–4 person calls (pasrom's clips favour Sortformer).
  - Echo on speaker (no headphones) calls.
- **Can it shrink?** Yes. It becomes a measurement ticket with a fixed method: start from pasrom's thresholds, score with pasrom's DER harness, and add Sortformer as a second arm. The design questions are gone.

### Detection and auto-stop rules on real usage (09)

- **Already answered by shipped code:**
  - The Zoom/Teams mic ambiguity is avoided in shipping code by using in-call **power assertions** instead of mic ownership: Teams keyword "call in progress" (its WebView holds "Video Wake Lock" while idle), Zoom display-sleep type, Webex "On a call", Chromium "WebRTC has active PeerConnections" with consent.
  - Prior-art thresholds: confirm in 2 × 3 s, stop after a 15 s end grace, 5 s cooldown between back-to-back calls, 4 h cap (pasrom); 120 s silence + 30 s countdown on summed mic + system level (Minute).
  - FaceTime's mic is reported by `com.apple.avconferenced`.
  - Mic-in-use alone falsely fires on voice messages; pasrom accepts that and has no duration filter.
- **Left for a hand-run check:**
  - Whether Zoom drops its assertion between back-to-back calls.
  - Teams idle mic vs assertion on Carbon's Mac.
  - Safari Meet (WebKit may not emit the Chromium WebRTC assertion).
  - Slack huddle (Electron, so it may hold the WebRTC assertion).
  - Dictation and voice memos (expected: mic only, no call assertion).
  - Muting in Meet (does the mic stay held?).
  - Overlapping calendar events.
- **Can it shrink?** Yes, if Carbon adds the power-assertion signal (a product-design decision for ticket 01). The run then becomes `pmset -g assertions` plus mic-in-use snapshots across the listed situations, not open-ended tuning. The initial ignore list can come from logging unmatched mic holders, as pasrom does.

### On-device summary quality (10)

- **Already answered by shipped code:**
  - The chunk-then-merge mechanics: token budget formula, line-boundary chunker, rolling "net-new only" JSON deltas against the accepted state, a deterministic merger, one JSON repair pass.
  - The anti-invention prompt rule.
  - Minute treats 4K as a debug-only floor and recommends 8K, a warning about Foundation Models' 4K limit.
- **Left for a hand-run check:**
  - Foundation Models' Summary quality in EN and FR.
  - Wall time for a 1 h Meeting (about 6 passes at 4K by Minute's formula).
  - Whether the growing state JSON squeezes later passes.
- **Can it shrink?** Yes. The design part is done, so it is a quality and latency run. Text quality needs no audio, so the run could use public meeting transcripts (AMI, or ticket 16's French pick) instead of waiting on ticket 06 **(inference)**.

### Transcription engine quality on real calls (14)

- **Already answered by shipped code:**
  - Both apps ship post-meeting-only Parakeet v3 via FluidAudio. pasrom ships it per track, the hybrid's post-pass.
  - The Parakeet language hint API exists and pasrom uses it against script drift. This turns Q2 into "pass the Meeting Language".
  - Q9: CTC vocabulary boosting ships in both apps, so the integration path is proven.
  - Q6 has a baseline merge rule (see 07).
  - A silence guard option: FluidAudio VAD trim at threshold 0.5, off by default in pasrom.
  - Minute shows what not to do: it turns Whisper's no-speech gates off.
  - A WER harness.
- **Left for a hand-run check:**
  - SpeechTranscriber vs Parakeet WER per stream and language on Carbon's calls. pasrom's small clips show Parakeet *behind* Whisper turbo (0.37 vs 0.29 on AMI EN), so the hybrid's gain is not a given.
  - Phantom text on muted stretches, with and without VAD.
  - Live cost of two SpeechTranscriber streams.
  - Post-pass time and memory on a base M1/M2.
  - Download sizes, Mac coverage, and the effect of name boosting.
- **Can it shrink?** A little. Q2 and Q9 shrink to confirmation, and Q6 moves to 07. The core WER and silence measurements on real calls remain, and pasrom's numbers raise the bar for keeping the Parakeet post-pass.
