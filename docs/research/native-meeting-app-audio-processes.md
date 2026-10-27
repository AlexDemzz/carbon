# Which processes carry call audio in native Zoom and Microsoft Teams on macOS

Researched 2026-10-27. Neither app is installed on the research Mac, so nothing here was measured by Carbon. Findings come from vendor docs, Apple docs, Homebrew casks, and the source code, tests and issue trackers of open-source meeting recorders that ran real calls. Where those projects measured something, I say so and cite the commit or issue. Labels used below:

- **Verified (source measured it):** a project reports a live measurement in code comments, a commit message or an issue.
- **Verified (packaging):** read from an app bundle listing, Info.plist, or an installer manifest.
- **Fixture only:** appears in a test fixture or a hard-coded list with no measurement behind it.
- **Inference:** my conclusion from the sources, not stated by any of them.
- **Unverified:** I found no primary source.

Context: Chrome and Safari were already measured in [ticket 05](../../.scratch/carbon-v1/issues/05-audio-capture-probe.md) (helper and GPU processes, exact-bundle taps empty, responsible-PID mapping). This note covers the two native apps.

Pinned sources used repeatedly:

- LokalBot (Swift, Core Audio process taps): [`stevyhacker/LokalBot@8ed6e55`](https://github.com/stevyhacker/LokalBot/tree/8ed6e554b60463e28a99ea098e8fd6ef9975936d)
- Mynah meeting-capture plan with proof-of-concept results: [`lukekerwin/mynah@1704804`](https://github.com/lukekerwin/mynah/blob/17048047050a0c3d12efbcf88cbe2b99c869e863/docs/plans/meeting-capture.md)
- shogo-ai meeting detector: [`shogo-labs/shogo-ai@afb1bf6`](https://github.com/shogo-labs/shogo-ai/blob/afb1bf6d29df14eacfc5d1cc7542409829e694fe/apps/desktop/src/detection/meeting-detector.ts)
- hex microphone activity: [`anomalyco/hex@df7f567`](https://github.com/anomalyco/hex/blob/df7f567dd8fa1c1231e8c7874fbdf15ecf6be369/src/microphone_activity.rs)
- live-mindmap investigation: [`daiki-beppu/live-mindmap` issue #1042](https://github.com/daiki-beppu/live-mindmap/issues/1042)

## Summary

| | Zoom (`us.zoom.xos`) | New Teams (`com.microsoft.teams2`) |
|---|---|---|
| Helper bundle IDs | `us.zoom.CptHost`, `us.zoom.caphost`, `us.zoom.airhost`, `us.zoom.aomhost`, plus `ZoomClips`, `ZoomPhone`, `ZoomHybridConf`, `Transcode` apps. **None start with `us.zoom.xos.`** | `com.microsoft.teams2.modulehost` ("Microsoft Teams ModuleHost"), `com.microsoft.teams2.helper` ("Microsoft Teams WebView", WebView2). All start with `com.microsoft.teams2.` |
| Who renders far-side audio | **Conflicting, not settled.** `us.zoom.xos` itself or `CptHost`/`caphost`, depending on the source | **Depends on the build.** ModuleHost in two reports (macOS 26.6 and 27.0), the main `MSTeams` process in one (2026-10-16). The WebView helper plays only chimes and short bursts |
| Who holds the mic | `us.zoom.xos` and `us.zoom.caphost` both report `IsRunningInput` in one measurement (macOS 14) | ModuleHost (`in:1 out:1`) in one report; the main process in another |
| Exact `bundleIDs = [app]` tap | Likely misses whatever a helper renders (inference) | Misses the call when ModuleHost carries it (verified: 0/20 with an exact match) |
| Prefix tap | `us.zoom.xos.` prefix does **not** match the helpers; you need `us.zoom.` or the responsible PID | `com.microsoft.teams2.` prefix covers every process (verified: 20/20) |
| Virtual driver | `ZoomAudioDevice.driver`, used for "share computer sound" | `MSTeamsAudioDevice.driver` ("Microsoft Teams Audio"), installed by default by the Teams pkg, used for "include computer sound" |
| Mic open while idle | Not reported for one call on its own. Back to back, Zoom "may keep the microphone active between calls" (Granola) | **Conflicting.** ModuleHost reported `in:1 out:1` for 20/20 samples while idle in one measurement, and `in:0` while idle in another |

What this means for Carbon (my opinion): pick tap targets **by family, not by exact bundle ID**. For Teams use the `com.microsoft.teams2.` namespace. For Zoom use the `us.zoom.` namespace, or better, the responsible PID that the Safari run already validated. Never pick a virtual Zoom or Teams device as the mic or the aggregate clock. Survive device-list changes during a call. Don't treat Teams' ModuleHost being open as proof of a Meeting.

## Zoom

### Process layout (verified, packaging)

- `zoom.us.app/Contents/Frameworks/` ships these helper apps: `CptHost.app`, `caphost.app`, `airhost.app`, `aomhost.app`, `ZoomClips.app`, `ZoomPhone.app`, `ZoomHybridConf.app`, `Transcode.app`, `ZMScreenshot.app`, and others. This is from an AX/bundle census of an installed Zoom ([llmos `Ax_analysis/zoom_us/meta.json`](https://github.com/HARSHITJAIS14/llmos/blob/main/Ax_analysis/zoom_us/meta.json)).
- Bundle IDs:
  - `us.zoom.aomhost`: `CFBundleIdentifier` in the Zoom Video SDK's `aomhost.app/Contents/Info.plist`, with `LSUIElement = true` ([zoom/videosdk-electron-sample](https://github.com/zoom/videosdk-electron-sample/blob/9a7946edecd322615e07143e939484819328cf1e/sdk/mac/ZoomVideoSDK/aomhost.app/Contents/Info.plist)).
  - `us.zoom.caphost` and `us.zoom.airhost`: both have their own preference domains (`~/Library/Preferences/us.zoom.caphost.plist`, `us.zoom.airhost.plist`) in the Homebrew `zoom-for-it-admins` zap stanza ([cask](https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/z/zoom-for-it-admins.rb)).
  - `us.zoom.CptHost` with process name `CptHost`: used as a real bundle ID in hex's tests and canonical map ([hex L63-L72, L530-L546](https://github.com/anomalyco/hex/blob/df7f567dd8fa1c1231e8c7874fbdf15ecf6be369/src/microphone_activity.rs#L63-L72)) and in LokalBot's tests ([AudioSourceMonitorTests](https://github.com/stevyhacker/LokalBot/blob/8ed6e554b60463e28a99ea098e8fd6ef9975936d/LokalBotTests/AudioSourceMonitorTests.swift)). Its Info.plist was not seen directly. Treat it as high but not packaging-verified.
- Current Zoom version in Homebrew: 7.2.2.88465 ([cask](https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/z/zoom.rb)).
- **None of the helper IDs start with `us.zoom.xos.`** live-mindmap read this from the installed app's Info.plists ([investigation doc, table row "Zoom"](https://github.com/daiki-beppu/live-mindmap/blob/research/mic-input-detection/docs/investigations/2026-10-14-mic-input-detection.md)). The Chrome-style rule "`<app>.` prefix" therefore never reaches Zoom's helpers. That is why hex and agent-native special-case Zoom to the whole `us.zoom.` namespace ([agent-native `call_activity.rs` L36-L37](https://github.com/BuilderIO/agent-native/blob/8f0bed71b0bcb3d1496416dc86a3101c71296dd3/templates/clips/desktop/src-tauri/src/call_activity.rs#L36-L37)).

### What each helper does

- **`CptHost` runs only during a meeting** (verified by long-standing admin practice, not by Zoom docs). Joel Bruner's macAdminTools script treats "`pgrep CptHost` succeeds" as "in a Zoom meeting" ([inMeeting_Zoom.sh, 2022](https://github.com/brunerd/macAdminTools/blob/c7bbc3b739ed7d01d03bced9f1c1ba694c29cb76/Scripts/inMeeting_Zoom.sh)). obsidian-meeting-copilot does the same: "the `CptHost` helper process only runs while you're in a call" ([probe.ts L6-L7](https://github.com/alvarolobato/obsidian-meeting-copilot/blob/96b1ad6711f659c5725143cce5f4e36f439d6277/src/detect/probe.ts#L6-L7)).
- **`aomhost` hosts Zoom Apps rendering contexts** (the Layers API), not core call media. "If `aomhost` package needs download, `runRenderingContext` returns non-success" ([zoom/skills layers-api.md](https://github.com/zoom/skills/blob/main/skills/zoom-apps-sdk/references/layers-api.md)). Concluding that it does not carry call audio is an **inference**.
- `caphost` and `airhost`: their roles are **unverified**. Biscotti's catalog calls `us.zoom.airhost` an "audio/screen-share helper", with the audio role marked unverified ([Biscotti meeting_apps README](https://github.com/scosman/Biscotti/blob/348f9d25180a5afc7d1ae97f9a4fc1caeefb17b0/specs/research/meeting_apps/README.md)).

### Who renders call audio and who holds the mic

The sources disagree. No one published a raw per-process log from a two-person Zoom call.

- **shogo-ai (verified, measured, macOS 14):** "both the app and its capture helper show up there [in `IsRunningInput`] under the vendor's bundle prefix (measured on macOS 14: `us.zoom.xos` for the app, `us.zoom.caphost` for its helper)" ([meeting-detector.ts L155-L162](https://github.com/shogo-labs/shogo-ai/blob/afb1bf6d29df14eacfc5d1cc7542409829e694fe/apps/desktop/src/detection/meeting-detector.ts#L155-L162)). It also says Zoom keeps "their capture helpers — alive for as long as the app is open", so the existence of a process means nothing and only `IsRunningInput` marks a live call. That contradicts the CptHost-only-in-meetings practice above, unless it means `caphost` rather than `CptHost` (**inference**: the two are different helpers).
- **LokalBot (claim, provenance unclear):** "Zoom routes call audio through `us.zoom.CptHost`". Its capture picks CptHost over the host when both have output running ([MeetingDetector.swift L1010-L1023](https://github.com/stevyhacker/LokalBot/blob/8ed6e554b60463e28a99ea098e8fd6ef9975936d/LokalBot/Services/MeetingDetector.swift#L1010-L1023), test `testZoomCaptureMapsCptHostAndPrefersItOverTheHost`). Elsewhere LokalBot calls `us.zoom.xos`'s own stream "call evidence (Zoom's)" ([MeetingAudioRecoveryTests L22-L38](https://github.com/stevyhacker/LokalBot/blob/8ed6e554b60463e28a99ea098e8fd6ef9975936d/LokalBotTests/MeetingAudioRecoveryTests.swift)). I found no commit that measured the CptHost claim.
- **FluidVoice (fixture only):** the test harness models `us.zoom.caphost` as output-only and the main app as input and output ([MeetingAutoDetectorTests L40-L56](https://github.com/altic-dev/FluidVoice/blob/main/Tests/FluidDictationIntegrationTests/MeetingAutoDetectorTests.swift)).
- **island-io/mila (fixture only):** "Zoom captures under a helper bundle ID rather than us.zoom.xos" (`us.zoom.CptHost`) ([MeetingAppTests L24-L26](https://github.com/island-io/mila/blob/main/MilaTests/MeetingAppTests.swift)).
- **live-mindmap (explicitly unmeasured):** "If [Zoom] handles input in a helper, the current rule **cannot catch it**" (translated).

Conclusion: a Zoom call involves `us.zoom.xos` plus at least one helper (`CptHost` and/or `caphost`). Which one renders the far side is **unverified**. Carbon's probe should log `IsRunningInput`/`IsRunningOutput` for every `us.zoom.*` process during a real call. Two outcomes follow (**inference**):

- An exact `bundleIDs = ["us.zoom.xos"]` tap works only if the main process renders the far side.
- A `us.zoom.` namespace tap, or one keyed on the responsible PID, works either way. All the helpers are launched by `zoom.us`, so responsibility should resolve to it. That is untested, but it is the same mechanism the Safari run validated.

### ZoomAudioDevice

- **Purpose (verified, vendor):** the Zoom macOS SDK changelog says "ZoomAudioDevice.driver and ZoomAudioDevice.kext added for share audio", and later "Updated the `ZoomAudioDevice.driver` and removed `ZoomAudioDevice.kext`" ([zoom/zoom-sdk-macos CHANGELOG](https://github.com/zoom/zoom-sdk-macos/blob/master/CHANGELOG.md)). Zoom staff on the dev forum: "ZoomAudioDevice.driver is used to sharing computer audio" ([devforum 51460, 2021-06-02](https://devforum.zoom.us/t/how-to-install-the-zoomaudiodevice-driver/51460)). It installs at `/Library/Audio/Plug-Ins/HAL/ZoomAudioDevice.driver` ([Homebrew cask uninstall list](https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/z/zoom-for-it-admins.rb)), and Zoom installs it on first use of "share sound" (community reports).
- **It shows up as an input device.** Recall.ai's Desktop SDK 2.0.8 (2026-03-13) "Added ZoomAudioDevice to mic capture blacklist on macOS" ([dsdk changelog](https://docs.recall.ai/docs/dsdk-changelog)). amanu found it is "hidden": setting it as the default input returns `noErr` but does nothing ([amanu pitfalls.md L260-L266](https://github.com/gsamat/amanu/blob/633251e0f5a32b080b159409665e9ac3f4db0a87/docs/pitfalls.md#L260-L266)). videorc saw it listed as an output device ([system-audio spike L177-L182](https://github.com/TheOrcDev/videorc/blob/4280537a5f582219b958f2e6784bce4dc08b86c3/docs/acceptance/2026-09-27-system-audio-spike.md#L177-L182)).
- **Effect on a process tap:** a process tap mixes "all of the specified processes' output audio". It is device-agnostic unless `deviceUID` pins one hardware device ([Apple: CATapDescription](https://developer.apple.com/documentation/coreaudio/catapdescription), [deviceUID](https://developer.apple.com/documentation/coreaudio/catapdescription/deviceuid)). Normal far-side playback therefore reaches the tap whichever output Zoom picks (**inference**). Whether "share computer sound" makes Zoom play other apps' audio back through its own process, which would put that audio into a Zoom tap a second time, is **unverified**. Community posts say the output switches to ZoomAudioDevice while sharing, but I found no primary source. Add "share sound on/off" to the probe protocol.
- macos-mic-keepwarm measured `coreaudiod` at 36.8% CPU at idle with the Zoom and Teams HAL plugins loaded, against 0.0% without them ([README L45-L55](https://github.com/drewburchfield/macos-mic-keepwarm/blob/0362fcf02df0cee835bfeda44c6c7911155bc13e/README.md#L45-L55)). That is one user's measurement.

### Mic held between calls

- Granola (vendor doc): "If you jump directly from one call to another, your meeting app (e.g. Zoom) may keep the microphone active between calls", and two Meetings can merge into one transcript ([How transcription works](https://docs.granola.ai/help-center/taking-notes/transcription)). The existing note already covers this. Use the calendar boundary.
- Holding the mic while idle with no call: no source reports it for Zoom. shogo-ai relies on `IsRunningInput` dropping when the call ends (**inference** that Zoom releases it).

## Microsoft Teams (new Teams)

### Process layout (verified, measured)

- `com.microsoft.teams2`: the main app, executable `MSTeams`.
- `com.microsoft.teams2.modulehost`: "Microsoft Teams ModuleHost" (shown as "Microsoft Teams MdlHst" in some lists).
- `com.microsoft.teams2.helper`: "Microsoft Teams WebView", the WebView2 helpers (several instances).

Sources: [Mynah plan L48-L51](https://github.com/lukekerwin/mynah/blob/17048047050a0c3d12efbcf88cbe2b99c869e863/docs/plans/meeting-capture.md#L48-L51) and [LokalBot #40](https://github.com/stevyhacker/LokalBot/issues/40). Every helper sits inside the `com.microsoft.teams2.` namespace. The Teams pkg also ships `com.microsoft.MSTeamsAudioDevice` as a pkg receipt next to `com.microsoft.teams2` ([Homebrew cask, version 26276.505.5234.9924](https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/m/microsoft-teams.rb)).

### Who renders call audio and who holds the mic

Three live measurements, which disagree on the main-vs-ModuleHost question:

1. **LokalBot #40 (macOS 26.6.2, real Teams call, Aug–Sep 2026):** "During a call, Teams emits output from bundle ids inside its namespace, never from `com.microsoft.teams2` itself: `com.microsoft.teams2.modulehost` … emits continuously, `com.microsoft.teams2.helper` (Microsoft Teams WebView) … only intermittently". Over 20 samples, an exact or `.helper`-only match detected Teams output 0/20 times, and the whole namespace 20/20 ([issue #40](https://github.com/stevyhacker/LokalBot/issues/40), [commit 7fe40d2](https://github.com/stevyhacker/LokalBot/commit/7fe40d28c8)). Also measured: "`translatePIDToProcessObject` fails for the Teams host PID because that process owns no Core Audio object" ([AudioSourceMonitorTests L164-L169](https://github.com/stevyhacker/LokalBot/blob/8ed6e554b60463e28a99ea098e8fd6ef9975936d/LokalBotTests/AudioSourceMonitorTests.swift)).
2. **LokalBot #179 (macOS 27.0, Jabra headset, 2026-10-06):** the reporter's process list shows "`com.microsoft.teams2.modulehost` (PID 20784) in:1 out:1" during the call. In a "Meet now" call the system track, tapped on a helper, still held the remote voices. The maintainer adds that a helper "also plays short bursts of audio" during a call ([issue #179](https://github.com/stevyhacker/LokalBot/issues/179)).
3. **Mynah PoC (2026-10-16):** "The main `com.microsoft.teams2` (MSTeams) process opened both input and output when the call connected (not ModuleHost). `com.microsoft.teams2.helper` (WebView) plays short sounds such as ringing and join chimes. Tapping every `com.microsoft.teams2*` process covers both." The tap captured the remote side at 48 kHz ([Mynah plan L1282](https://github.com/lukekerwin/mynah/blob/17048047050a0c3d12efbcf88cbe2b99c869e863/docs/plans/meeting-capture.md)).

**Inference:** which process owns call media changes with the Teams build or configuration. Recall.ai shipped "Fix for meeting detection for Teams Desktop v26246+ on macOS" on 2026-10-14 ([dsdk changelog 2.0.38](https://docs.recall.ai/docs/dsdk-changelog)), which hints at a recent change in Teams' process model, but the changelog doesn't say what changed. What every source agrees on: **a `com.microsoft.teams2.` namespace tap (or the responsible PID) catches the call, and an exact `com.microsoft.teams2` tap can come back empty.**

### Mic held while idle: conflicting

- LokalBot maintainer, measured: "with Teams launched and idle, 20 samples over 20 s: `com.microsoft.teams2.modulehost` reported `isRunningOutput` *and* `isRunningInput` true in 20/20, while all three `com.microsoft.teams2.helper` processes reported false in 60/60". LokalBot therefore treats ModuleHost as capture-only and never as call evidence ([MeetingDetector.swift L141-L156](https://github.com/stevyhacker/LokalBot/blob/8ed6e554b60463e28a99ea098e8fd6ef9975936d/LokalBot/Services/MeetingDetector.swift#L141-L156)).
- LokalBot #179 reporter, measured on macOS 27.0: "Teams open, no call: modulehost not running input (in:0)". "Teams call active: modulehost in:1 out:1".
- Mynah: "Teams keeps output open through silence", which caused a false silent-tap alarm. Mynah changed its rule to "only exact zeros for 60 s".

**Inference:** ModuleHost may keep the mic open in some states, for example after a call or with a device-test preview, and not in others. Until Carbon measures it, Detection should not start a Meeting on "Teams namespace holds the mic" alone. It should also add a second signal (calendar event, or the Teams window title "`<name> | Microsoft Teams`" read through AX, as Mynah does) or a minimum duration. LokalBot's 12 s sustained-audio gate failed on scheduled Teams joins because helper bursts never lasted 12 s ([#179](https://github.com/stevyhacker/LokalBot/issues/179)).

### Microsoft Teams Audio (`MSTeamsAudioDevice.driver`)

- **Purpose (verified, vendor):** "On a Mac, you'll need to install the latest Teams audio driver in order to include computer audio in a Teams meeting", followed by a restart ([Microsoft Support: share sound](https://support.microsoft.com/en-US/teams/meetings/share-sound-from-your-computer-in-microsoft-teams-meetings-or-live-events)). It installs at `/Library/Audio/Plug-Ins/HAL/MSTeamsAudioDevice.driver` and comes with the Teams pkg by default ([Homebrew cask](https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/m/microsoft-teams.rb)).
- **It appears as an input device named "Microsoft Teams Audio"** ([OpenOats #75 screenshot](https://github.com/yazinsai/OpenOats/issues/75)) and as an output device ([videorc spike](https://github.com/TheOrcDev/videorc/blob/4280537a5f582219b958f2e6784bce4dc08b86c3/docs/acceptance/2026-09-27-system-audio-spike.md#L177-L182)). Mynah: it "must never be used as a capture or clock device".
- **It changes the device graph mid-call (verified, measured by one project):** "When joining a call (especially with screen sharing + audio), this plugin dynamically creates/destroys virtual I/O devices, triggering a Core Audio device graph reconfiguration. This invalidates all existing `AudioDeviceID` integer handles." Their HAL-API mic capture broke until reboot. Their fix was AVAudioEngine with a restart on `AVAudioEngineConfigurationChange` ([gday-meetings mic-reconnect-teams.md](https://github.com/rankun203/gday-meetings/blob/6b51d2110720e99a07d99081be1f333cf0b5c61c/docs/mic-reconnect-teams.md)). For Carbon (**inference**): the tap's private aggregate device and the mic path must listen to `kAudioHardwarePropertyDevices` / configuration changes and rebuild, instead of holding device IDs for the whole Meeting.
- **Duplicate or missing audio from the driver:** a Vmaker support article says that with Teams "include computer audio", "the audio driver on your computer switches from Vmaker to Microsoft Teams", so Vmaker loses computer audio ([Vmaker](https://support.vmaker.com/en/articles/6765057-computer-audio-not-captured-while-sharing-screen-on-microsoft-teams)). It names no OS and no mechanism, so it is low trust. A process tap does not depend on the output device (Apple docs above), so it should keep working. That is an **inference**, and the probe should test it.

## Issues reported by other process-tap apps

- **LokalBot (process taps):** mic-only recordings for every Teams call until the namespace match ([#40](https://github.com/stevyhacker/LokalBot/issues/40)). Missed auto-detection of scheduled Teams joins ([#179](https://github.com/stevyhacker/LokalBot/issues/179)). A tap watchdog that "alternated between two Teams siblings every 10–15 s for 21 minutes", where a pause moved the tap onto an empty helper ([RecordingController.swift L89-L97](https://github.com/stevyhacker/LokalBot/blob/8ed6e554b60463e28a99ea098e8fd6ef9975936d/LokalBot/Services/RecordingController.swift)). Lesson: tap the whole family in one tap and don't hop between siblings. A "silent capture" banner that fires correctly when the far side joins late ([#47](https://github.com/stevyhacker/LokalBot/issues/47)).
- **OpenOats:** Teams auto-detect missed. The maintainer's diagnosis was a hard-coded bundle list ([#75](https://github.com/yazinsai/OpenOats/issues/75)).
- **Recall.ai Desktop SDK:** Zoom URL detection needs one Zoom restart after the SDK first initializes ([FAQ](https://docs.recall.ai/docs/desktop-recording-sdk-faq)). ZoomAudioDevice is excluded as a mic (2.0.8). "Fixed audio issue when background audio was playing while in Teams Desktop PIP window on macOS" (2.0.27) and "Fixed Zoom computer-audio disconnected handling on macOS" (2.0.34) ([changelog](https://docs.recall.ai/docs/dsdk-changelog)). Its [Core Audio taps post](https://www.recall.ai/blog/core-audio-taps) says only that native apps are "usually associated with the app's own process group". It names no processes.
- **Granola:** captures "the combined audio stream from your system" and "cannot isolate audio from individual applications" ([transcription](https://docs.granola.ai/help-center/taking-notes/transcription)), so it sidesteps helper targeting. It reports Zoom keeping the mic between back-to-back calls.
- **AudioCap, AudioTee, Meetily, Omi:** no Zoom- or Teams-specific handling or issues found. Omi matches `<catalog id>.<suffix>` helpers, which covers Teams but not Zoom's `us.zoom.CptHost` ([ConferencingApps.swift L130-L138](https://github.com/BasedHardware/omi/blob/b1a9572f83e164ce66c50826287fa6b3e9f2b7ee/desktop/macos/Desktop/Sources/ConferencingApps.swift)). The search hit GitHub's code-search rate limit, so AudioCap/AudioTee/Meetily were checked only through the earlier note.
- **OBS (ScreenCaptureKit app audio, not a process tap):** forum guides say to pick `zoom.us` in Application Audio Capture, which "sometimes" needs toggling before it works. No official OBS statement on helpers. Low trust.
- **Hyprnote/Char/Anarlog:** detects Zoom/Teams through AX ("leave meeting", "hang up") and the mic, as the existing note covers. No helper-specific capture issue found.

## Apple facts used

- `CATapDescription.bundleIDs`: "each String holds the bundle ID of a process to tap or exclude", macOS 26.0+ ([docs](https://developer.apple.com/documentation/coreaudio/catapdescription/bundleids)). Carbon measured that this is an exact match (Chrome run 1).
- `isProcessRestoreEnabled`: "save tapped processes by bundle ID when they exit, and restore them to the tap when they start up again", macOS 26.0+ ([docs](https://developer.apple.com/documentation/coreaudio/catapdescription/isprocessrestoreenabled)). This matters for Zoom's per-meeting `CptHost` and for Teams helpers that restart (**inference**: a bundle-ID tap with restore re-attaches without a rebuild, but it still needs every helper ID listed).
- The tap's stream is "a mix of all of the specified processes' output audio" ([CATapDescription](https://developer.apple.com/documentation/coreaudio/catapdescription)). Tapping the main app and its helpers together does not duplicate audio unless two processes render the same content (**inference**).

## Checklist for the probe (ticket 05)

- [ ] Zoom call: log every `us.zoom.*` process (`IsRunningInput`/`IsRunningOutput`, PID, responsible PID) before, during and after the call, and between two back-to-back calls.
- [ ] Zoom: compare an exact `us.zoom.xos` tap, a `us.zoom.` namespace tap, and the global tap. Repeat with "share sound" on to look for duplicated or foreign audio.
- [ ] Teams call: log `com.microsoft.teams2*` the same way. Note the Teams build (Help → About). Check whether the main process or ModuleHost carries the far side.
- [ ] Teams idle (launched, no call; and right after hanging up): does ModuleHost report `IsRunningInput`?
- [ ] Teams "include computer sound": does the device list change mid-call, and does the tap or aggregate survive?
- [ ] Confirm that `responsibility_get_pid_responsible_for_pid` maps `CptHost`/`caphost` → `zoom.us` and ModuleHost/WebView → `MSTeams`.
