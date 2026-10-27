# Verifying the audio capture probe's findings

Researched 2026-10-27. This note checks the probe's findings ([ticket 05](../../.scratch/carbon-v1/issues/05-audio-capture-probe.md), Runs 1, 2, 5 and Progress) against three kinds of source: Apple's macOS 26 SDK headers (Xcode 26.4, `xcrun --show-sdk-path`), Apple's documentation and Developer Forums, and open-source apps that use Core Audio process taps. Each claim gets a verdict: **confirmed**, **contradicted**, **partly confirmed** or **no source found**. Anything I concluded myself, rather than read in a source, is marked **(inference)**. Zoom and Teams native processes are out of scope; another note covers them.

Background for the claims below: [local-meeting-capture.md](local-meeting-capture.md).

## Sources and pins

Header paths are relative to `$(xcrun --show-sdk-path)/System/Library/Frameworks/CoreAudio.framework/Headers/`.

| Source | Pin | What it is |
|---|---|---|
| [insidegui/AudioCap](https://github.com/insidegui/AudioCap/tree/6f609e8ad1b1e11fa0e8edbe91864cb099f00de3) | `6f609e8` | Apple-sample-style per-process tap reference |
| [ronitsingh10/FineTune](https://github.com/ronitsingh10/FineTune/tree/2285279d36d3f8115c1c2d4aecd904f1bdf96a51) | `2285279` | Shipping per-app volume mixer (~9.9k stars) |
| [pasrom/meeting-transcriber](https://github.com/pasrom/meeting-transcriber/tree/1765408a99b4c1360735648df7f41055e647f4a5) | `1765408` | Meeting transcriber with per-app taps |
| [hakanotal/FreeAudio](https://github.com/hakanotal/FreeAudio/tree/2a8e03a96d15fe7d64c429ece121a887ac81bf16) | `2a8e03a` | Per-app EQ; `docs/LESSONS.md` logs measured tap behaviour on macOS 27 |
| [andreypudov/core-eq](https://github.com/andreypudov/core-eq/tree/372803e8c304eb55a2478156fec92c1ee1916701) | `372803e` | System EQ that uses `bundleIDs` exclusion, measured on macOS 27 |
| [sozercan/kaset](https://github.com/sozercan/kaset/tree/4c59ff259d853f1cc328597f5adccf2a291c2fa7) | `4c59ff2` | YouTube Music client that taps its own WebKit helpers |
| [tohmsc/resonant-community](https://github.com/tohmsc/resonant-community/tree/80aa8ecb1bffbe26655d989cbb764f82ebfebdaa) | `80aa8ec` | Meeting app that uses macOS 26 `bundleIDs` taps |
| [fastrepl/anarlog](https://github.com/fastrepl/anarlog/tree/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9) (Hyprnote/Char) | `7165aba` | Meeting notes app, global tap |
| [OpenWhispr/openwhispr](https://github.com/OpenWhispr/openwhispr/tree/ec5852811c09cd7b76992fbbddaba49cc5acb523) | `ec58528` | Dictation and meeting app (~10k stars) |
| [turantekin/Parrot](https://github.com/turantekin/Parrot/tree/f9f2e2beab374b641d445a3390e15b132090ecd6), [hbofz/Ogi](https://github.com/hbofz/Ogi/tree/7119d458b95be94981aa820730132ac68f8f8841), [mameli/Takku](https://github.com/mameli/Takku/tree/c654584290a8414625156c33343a6b19a149273f), [nolanmak/FlyOnTheWall](https://github.com/nolanmak/FlyOnTheWall/tree/357fa595a8c3bf033359d2c759465071d08d9447) | as linked | Smaller call detectors with measured notes |

I also looked for Recap and Omi: Omi's capture is already covered in [local-meeting-capture.md](local-meeting-capture.md), and I did not find a Recap repository with tap code. A GitHub code search for `responsibility_get_pid_responsible_for_pid` together with `kAudioProcessPropertyPID` returned about 30 repositories. Most are mixers and EQs: OnlySwitch, OmniWM, Sapphire, SoundMenu, Sonexis and others.

## Claim 1: a tap on the browser's bundle ID misses audio from its helper processes

**Verdict: confirmed.** Open-source tappers handle helpers in four ways: by process-object lists, by responsible PID, by executable path, or by bundle-ID prefix. None of them relies on the main bundle ID alone, except Resonant (see "Counter-example" below).

**Evidence that the bundle ID misses helpers:**

- Carbon's own measurements:
  - Run 1: `bundleIDs = ["com.google.Chrome"]` got zero callbacks for 96 s.
  - Run 2: `com.apple.Safari` got zero callbacks, because the audio is rendered by `com.apple.WebKit.GPU`.
- core-eq measured the same thing for exclusion. "Apps that play through a helper process cannot be excluded this way. Safari's sound comes from `com.apple.WebKit.GPU`; excluding Safari's identifier, **or even the helper's**, left it in the tap. Only the helper's process object removed it, and that helper serves every WebKit app at once" ([AppExclusion.swift#L23-L27](https://github.com/andreypudov/core-eq/blob/372803e8c304eb55a2478156fec92c1ee1916701/CoreEQ/Audio/Capture/AppExclusion.swift#L23-L27)).
- pasrom measured the same failure for Safari. "Measured: `App audio tap: 1 PID(s) [Safari(692)]` while the audio came from `com.apple.WebKit.GPU(21403)`. The tap was valid and recorded an hour of silence" ([ProcessResponsibility.swift#L116-L120](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/tools/audiotap/Sources/ProcessResponsibility.swift#L116-L120)).
- kaset: "Tapping our own PID therefore captures silence … filters to WebKit processes whose ownership can be proven for this app" ([ProcessTapHelper.swift#L12-L16](https://github.com/sozercan/kaset/blob/4c59ff259d853f1cc328597f5adccf2a291c2fa7/Sources/Kaset/Services/Audio/ProcessTapHelper.swift#L12-L16)).

**How the open-source tappers handle it:**

| Approach | Who | Notes |
|---|---|---|
| Responsible PID, then the parent-PID chain | FineTune [AudioProcessMonitor.swift#L103-L140](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Monitors/AudioProcessMonitor.swift#L103-L140) | "First try Apple's responsibility API (works for XPC services like Safari's WebKit processes)", then "walking up the process tree (works for Chrome/Brave helpers)". |
| Executable-path group plus responsible PID | pasrom [ProcessResponsibility.swift#L5-L22](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/tools/audiotap/Sources/ProcessResponsibility.swift#L5-L22) | Path prefix works for Chrome and Electron, whose helpers live inside the bundle. Responsibility is added for Safari. |
| Responsibility, then outermost `.app`, then the process's own bundle | FreeAudio [LESSONS.md#L12](https://github.com/hakanotal/FreeAudio/blob/2a8e03a96d15fe7d64c429ece121a887ac81bf16/docs/LESSONS.md#L12) | "Electron helpers can be `.app` bundles themselves", so checking the process's own bundle first is wrong. |
| WebKit bundle-ID allowlist plus parent PID, child PIDs and legacy process name | kaset [#L236-L300](https://github.com/sozercan/kaset/blob/4c59ff259d853f1cc328597f5adccf2a291c2fa7/Sources/Kaset/Services/Audio/ProcessTapHelper.swift#L236-L300) | It refuses to tap when ownership cannot be proven. |
| Bundle-ID prefix (`<id>.`) | pasrom detection [MicInputDetector.swift#L35-L41](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/MicInputDetector.swift#L35-L41), Omi | Used for mic detection only. For WebKit it leaks: Carbon Run 2 measured Copper's GPU process leaking in, and FreeAudio's [LESSONS.md#L13](https://github.com/hakanotal/FreeAudio/blob/2a8e03a96d15fe7d64c429ece121a887ac81bf16/docs/LESSONS.md#L13) warns: "Never tap or exclude by that bundle ID." |
| Nearest enclosing bundle (display only) | AudioCap [AudioProcessController.swift#L147-L148](https://github.com/insidegui/AudioCap/blob/6f609e8ad1b1e11fa0e8edbe91864cb099f00de3/AudioCap/ProcessTap/AudioProcessController.swift#L147-L148), [#L227-L235](https://github.com/insidegui/AudioCap/blob/6f609e8ad1b1e11fa0e8edbe91864cb099f00de3/AudioCap/ProcessTap/AudioProcessController.swift#L227-L235) | AudioCap taps a single process object ([ProcessTap.swift#L92](https://github.com/insidegui/AudioCap/blob/6f609e8ad1b1e11fa0e8edbe91864cb099f00de3/AudioCap/ProcessTap/ProcessTap.swift#L92)) and does not group helpers. |

**Counter-example.** On macOS 26, Resonant passes only the browsers' *main* bundle IDs, lowercased (`"com.google.chrome"`), to `bundleIDs` with `isProcessRestoreEnabled` ([SystemAudioCapture.swift#L117-L139](https://github.com/tohmsc/resonant-community/blob/80aa8ecb1bffbe26655d989cbb764f82ebfebdaa/Sources/Resonant/Features/Meetings/Audio/SystemAudioCapture.swift#L117-L139), [BrowserSupport.swift#L10](https://github.com/tohmsc/resonant-community/blob/80aa8ecb1bffbe26655d989cbb764f82ebfebdaa/Sources/Resonant/Shared/BrowserSupport.swift#L10)). Run 1 suggests this setup would capture nothing from Chrome **(inference)**. I found no measurement in that repo.

## Claim 2: semantics of `CATapDescription.bundleIDs` and process restore

**Verdict: confirmed for exact matching.** Helpers are not included. `processRestoreEnabled` exists and is documented, but it restores processes **by bundle ID only**.

**What the header says:**

- `bundleIDs`: "An Array of Strings where each String holds the bundle ID of a process to tap or exclude." `API_AVAILABLE(macos(26.0))` (`CATapDescription.h:131-136`). The header says nothing about children or helpers. Apple's [documentation page](https://developer.apple.com/documentation/coreaudio/catapdescription/bundleids) has the same single sentence.
- `processRestoreEnabled` (Swift: `isProcessRestoreEnabled`): "True if this tap should save tapped processes by bundle ID when they exit, and restore them to the tap when they start up again." `API_AVAILABLE(macos(26.0))` (`CATapDescription.h:162-167`; [doc](https://developer.apple.com/documentation/coreaudio/catapdescription/isprocessrestoreenabled)).
- `kAudioTapPropertyDescription`: "This property can be used to modify and set the description of an existing tap" (`AudioHardware.h`, Tap Object Properties, around line 2015). A running tap's process list can therefore be changed in place.

**What the open-source measurements show:**

- FreeAudio S5: "with `bundleIDs = [app]` and `processRestoreEnabled`, a tap follows the app across quit and relaunch … and **ignores apps with other bundle IDs**. A tap made with an empty process list and only `bundleIDs` picks the app up when it starts" ([LESSONS.md#L24](https://github.com/hakanotal/FreeAudio/blob/2a8e03a96d15fe7d64c429ece121a887ac81bf16/docs/LESSONS.md#L24)).
- core-eq: "`processRestoreEnabled` is what keeps it excluded. Without it an app that launches, or quits and comes back, after the tap was made is tapped like any other". It also says the default is undocumented and sets the flag explicitly ([AppExclusion.swift#L20-L22](https://github.com/andreypudov/core-eq/blob/372803e8c304eb55a2478156fec92c1ee1916701/CoreEQ/Audio/Capture/AppExclusion.swift#L20-L22), [#L64-L67](https://github.com/andreypudov/core-eq/blob/372803e8c304eb55a2478156fec92c1ee1916701/CoreEQ/Audio/Capture/AppExclusion.swift#L64-L67)).
- core-eq: listing the *helper's* bundle ID did not work either for `com.apple.WebKit.GPU` (exclusion case, see claim 1).
- FreeAudio S4: setting `kAudioTapPropertyDescription` with a longer process list on a running tap "takes ~7 ms, the new process is captured within ~30 ms, there is no callback gap longer than one buffer, and the format stays the same. 100 alternating updates: no failures" ([LESSONS.md#L23](https://github.com/hakanotal/FreeAudio/blob/2a8e03a96d15fe7d64c429ece121a887ac81bf16/docs/LESSONS.md#L23)).

**Still open:**

- Whether `bundleIDs = ["com.google.Chrome.helper"]` covers Chrome's helpers. It is untested in Carbon. core-eq's WebKit result points to "maybe not" **(inference)**.
- Whether matching is case-sensitive: **no source found**.

## Claim 3: mapping helper processes to their owning app

**Verdict: confirmed.** `responsibility_get_pid_responsible_for_pid` is used by shipping open-source apps. It has no public header. Public alternatives exist, but each misses some cases.

**What the SDK shows.** The symbol is exported by `/usr/lib/system/libquarantine.dylib` (the SDK stub `usr/lib/system/libquarantine.tbd:28` lists `_responsibility_get_pid_responsible_for_pid`). No header in `usr/include` declares it. It is therefore linkable but private.

**Who uses it:**

- FineTune, through `dlsym(RTLD_DEFAULT, …)`, commented "This is what Activity Monitor uses to show the correct parent for XPC services" ([AudioProcessMonitor.swift#L90-L101](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Monitors/AudioProcessMonitor.swift#L90-L101)).
- pasrom, through `dlsym`, which logs "pid 2032 [com.apple.WebKit.GPU] -> responsible 707 [com.apple.Safari]" measured on macOS 26.5. Its App Store build drops the symbol: "shipping the string invites an automated review flag" ([ProcessResponsibility.swift#L14-L40](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/tools/audiotap/Sources/ProcessResponsibility.swift#L14-L40)).
- FreeAudio uses it as the first step of its grouping chain (claim 1).

**Pitfall that matters for Carbon:** pasrom widens to responsible processes only when "`rootPID` is its OWN responsible party, i.e. a normally launched app. A process started from a shell or script is attributed to the launcher" ([#L122-L136](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/tools/audiotap/Sources/ProcessResponsibility.swift#L122-L136)). FreeAudio notes the same for TCC: "macOS judges a process started from a terminal by the terminal app's grants (the responsible process)" ([LESSONS.md#L42](https://github.com/hakanotal/FreeAudio/blob/2a8e03a96d15fe7d64c429ece121a887ac81bf16/docs/LESSONS.md#L42)).

**Public alternatives and where each fails:**

- **Parent PID** (`proc_pidinfo(PROC_PIDTBSDINFO).pbi_ppid` or `sysctl KERN_PROC`): works for Chrome helpers (FineTune fallback). It fails for WebKit XPC services, which are reparented to launchd. Kaset says: "survives even when their Unix parent PID has been reparented to launchd" ([ProcessTapHelper.swift#L384-L389](https://github.com/sozercan/kaset/blob/4c59ff259d853f1cc328597f5adccf2a291c2fa7/Sources/Kaset/Services/Audio/ProcessTapHelper.swift#L384-L389)).
- **Executable path inside the `.app`** (`proc_pidpath`): works for Chrome and Electron (Hyprnote, FluidVoice, pasrom). It fails for Safari, whose WebKit helpers live under `WebKit.framework` (pasrom #L7-L12).
- **`NSRunningApplication`**: helpers are not running applications. Hyprnote resolves the outermost `.app` through `bundleURL`, which helps Chrome but not WebKit (see [local-meeting-capture.md](local-meeting-capture.md)).
- **Legacy Process Manager name and launcher** (`GetProcessForPID` → "Kaset Graphics and Media", launcher "Kaset Networking"): kaset uses it for WebKit ownership ([#L384-L401](https://github.com/sozercan/kaset/blob/4c59ff259d853f1cc328597f5adccf2a291c2fa7/Sources/Kaset/Services/Audio/ProcessTapHelper.swift#L384-L401)). These APIs are deprecated, and matching on names is heuristic.
- **Audit tokens**: no source found that maps an audio process to its owning app this way.

## Claim 4: a missing System Audio Recording permission gives silence with no error; permission preflight

**Verdict: confirmed.** There is no public API to check the permission. A private TCC preflight exists, and there is one unofficial public-API signal.

**What Apple says.** An Apple engineer, in the accepted answer on [Developer Forums 756783](https://developer.apple.com/forums/thread/756783):

> "There is no API to determine whether an app still has permission to capture system audio … If you are getting silent buffers, this could be an indication that the user might have revoked the app's permission."

Apple's [sample page](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) says only that "The first time you start recording from an aggregate device that contains a tap, the system prompts you".

**Other reports of zeros with no error:**

- Meetily's code comment: "If permission is denied, the tap will return silence (all zeros)" (see [local-meeting-capture.md](local-meeting-capture.md)).
- [dev.to "2000 buffers of nothing"](https://dev.to/nickdelv/2000-buffers-of-nothing-3i8) reports `noErr` everywhere. That source is secondary.

**Private preflight:**

- AudioCap `dlopen`s `TCC.framework` and calls `TCCAccessPreflight("kTCCServiceAudioCapture", nil)`. It maps `0` to authorized, `1` to denied and anything else to unknown. It re-checks on `didBecomeActive` and sits behind `ENABLE_TCC_SPI` ([AudioRecordingPermission.swift#L19-L25](https://github.com/insidegui/AudioCap/blob/6f609e8ad1b1e11fa0e8edbe91864cb099f00de3/AudioCap/ProcessTap/AudioRecordingPermission.swift#L19-L25), [#L65-L73](https://github.com/insidegui/AudioCap/blob/6f609e8ad1b1e11fa0e8edbe91864cb099f00de3/AudioCap/ProcessTap/AudioRecordingPermission.swift#L65-L73)).
- FreeAudio measured the return codes: "returns 2 before the user was ever asked (0 = authorized, 1 = denied)" ([LESSONS.md#L11](https://github.com/hakanotal/FreeAudio/blob/2a8e03a96d15fe7d64c429ece121a887ac81bf16/docs/LESSONS.md#L11)).
- FineTune ([AudioRecordingPermission.swift](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Permission/AudioRecordingPermission.swift)) and Hyprnote ([tcc/swift-lib/src/lib.swift](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/crates/tcc/swift-lib/src/lib.swift)) use the same preflight.

**Unofficial public-API signal.** A non-Apple reply in the same forum thread says: "Updating `kAudioTapPropertyDescription` will return `kAudioDevicePermissionsError` when System Audio Recording Only is disabled. That is the only reliable way I have found." I have not verified this.

**Side notes:**

- pasrom states that Screen Recording is "one of two sufficient grants for the app-audio tap" and that Audio Recording "has no preflight API" ([PermissionHealthCheck.swift#L74-L84](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/PermissionHealthCheck.swift#L74-L84)). I found no Apple source for the Screen Recording part.
- pasrom's [PermissionHealthCheck.swift#L264-L268](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/PermissionHealthCheck.swift#L264-L268) makes the same point for the microphone: silence is not failure, because a working but muted mic also delivers all-zero buffers.

**Carbon-specific note.** A CLI probe run from a terminal is judged by the *terminal's* grant (FreeAudio L42). This is consistent with the Progress note's "confirm which terminal".

## Claim 5: the tap and aggregate keep running across a default-output switch (speakers to AirPods HFP), at 48 kHz

**Verdict: partly confirmed.** It is confirmed for Carbon's aggregate shape: tap only, no sub-device. Most other apps restart defensively because their aggregates contain the output device. Apple documents nothing on this.

**Supporting:**

- Run 5 (measured).
- FreeAudio: "A device-scoped rest tap … survives default-output switches without errors" ([LESSONS.md#L20](https://github.com/hakanotal/FreeAudio/blob/2a8e03a96d15fe7d64c429ece121a887ac81bf16/docs/LESSONS.md#L20)).

**Why others restart.** AudioCap, pasrom and kaset put the **default output as `MainSubDevice`** ([AudioCap ProcessTap.swift#L110-L131](https://github.com/insidegui/AudioCap/blob/6f609e8ad1b1e11fa0e8edbe91864cb099f00de3/AudioCap/ProcessTap/ProcessTap.swift#L110-L131), [pasrom AggregateDescription.swift#L25-L40](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/tools/audiotap/Sources/AppAudioCapture%2BAggregateDescription.swift#L25-L40)), so they rebuild on a device change:

- pasrom logs "default output device changed, recreating tap" ([Restart.swift#L17-L33](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/tools/audiotap/Sources/AppAudioCapture%2BRestart.swift#L17-L33)).
- Hyprnote restarts on `DefaultOutputChanged` (see [local-meeting-capture.md](local-meeting-capture.md)).
- Resonant takes a different route. It pins the aggregate clock to the built-in output "so the IO callback keeps firing even if the user's active output device disappears (Bluetooth disconnect, HDMI unplug)" ([SystemAudioCapture.swift#L100-L103](https://github.com/tohmsc/resonant-community/blob/80aa8ecb1bffbe26655d989cbb764f82ebfebdaa/Sources/Resonant/Features/Meetings/Audio/SystemAudioCapture.swift#L100-L103)).

**On the 48 kHz rate.** The header says `kAudioTapPropertyFormat` is "the current data format for the tap", which implies it can change. Hyprnote re-reads it every 128 buffers. Run 5 saw no change, but keep the `tapFormatChanged` listener **(inference)**.

## Claim 6: an empty tap gets no IO callbacks at all

**Verdict: confirmed.** The header explains it: this is how `TapAutoStart` behaves, not a fault. One nuance changes the v1 rule (see Recommendations).

- `kAudioAggregateDeviceTapAutoStartKey`: "a non-zero value indicates that this aggregate device's start should wait for the first tap that receives audio. When this key is used, calling AudioDeviceStart with the aggregate device will wait until a tapped process begins receiving its first audio" (`AudioHardware.h:1635-1645`). The probe sets this key to `true` (`probe.swift`, `TapRecorder.start`).
- FreeAudio, with measurements:
  - "Tapping an idle process: start returns instantly and the IOProc gets no callbacks until the process plays."
  - "A tap whose processes are all silent gets no callbacks."
  - "once an aggregate's IO has started it keeps running after its source stops (~94 callbacks/s)", and coreaudiod holds a `PreventUserIdleSystemSleep` assertion while it runs.

  Sources: [LESSONS.md#L17](https://github.com/hakanotal/FreeAudio/blob/2a8e03a96d15fe7d64c429ece121a887ac81bf16/docs/LESSONS.md#L17), [#L21](https://github.com/hakanotal/FreeAudio/blob/2a8e03a96d15fe7d64c429ece121a887ac81bf16/docs/LESSONS.md#L21), [#L26-L27](https://github.com/hakanotal/FreeAudio/blob/2a8e03a96d15fe7d64c429ece121a887ac81bf16/docs/LESSONS.md#L26-L27).

**So "no callbacks" means no tapped process has produced output since the tap started.** That covers both "wrong processes" and "the right process, not playing yet". After the first callback, a tap that stops capturing the real mix shows up as **full-rate zeros**, never as missing callbacks. A forum report describes exactly this: "All-zero buffers from a broken tap are indistinguishable from legitimate silence … `kAudioProcessPropertyIsRunningOutput` … a muted Zoom call still reports `true`". The author's only fix is a full rebuild. The thread is unanswered ([Developer Forums 825780](https://developer.apple.com/forums/thread/825780)).

**Related:**

- Process objects exist before a process plays ([LESSONS.md#L38](https://github.com/hakanotal/FreeAudio/blob/2a8e03a96d15fe7d64c429ece121a887ac81bf16/docs/LESSONS.md#L38)).
- Core Audio **reuses process object IDs** after exit, so never cache them ([#L32](https://github.com/hakanotal/FreeAudio/blob/2a8e03a96d15fe7d64c429ece121a887ac81bf16/docs/LESSONS.md#L32)).

## Claim 7: `corespeechd` (`com.apple.CoreSpeech`) intermittently reports `IsRunningInput`

**Verdict: confirmed.** Several independent detectors name it in an ignore list. None of these sources is Apple's.

**Explicit ignores:**

| Project | How it ignores CoreSpeech | Source |
|---|---|---|
| OpenWhispr | Skips `isRunningInput` when the bundle ID is `com.apple.CoreSpeech`, with the comment "CoreSpeech also processes ordinary playback, so it is not evidence of a meeting" | [macos-mic-listener.swift#L244-L245](https://github.com/OpenWhispr/openwhispr/blob/ec5852811c09cd7b76992fbbddaba49cc5acb523/resources/macos-mic-listener.swift#L244-L245) |
| Parrot | Ignores `com.apple.corespeechd` and `com.apple.CoreSpeech` | [CallDetector.swift#L152-L156](https://github.com/turantekin/Parrot/blob/f9f2e2beab374b641d445a3390e15b132090ecd6/Parrot/Services/CallDetector.swift#L152-L156) |
| Takku | `ignoredProcesses = ["com.apple.CoreSpeech"]` ("Listening for 'Hey Siri' is not a call") | [CallDetector.swift#L33-L34](https://github.com/mameli/Takku/blob/c654584290a8414625156c33343a6b19a149273f/Takku/Capture/CallDetector.swift#L33-L34) |
| Ogi | `alwaysListening = ["com.apple.CoreSpeech"]`, plus a "slow to arm" debounce because corespeechd "takes the microphone in bursts shorter than a second" | [Signals.swift#L308-L322](https://github.com/hbofz/Ogi/blob/7119d458b95be94981aa820730132ac68f8f8841/Sources/OgiCore/Signals.swift#L308-L322), [#L49-L51](https://github.com/hbofz/Ogi/blob/7119d458b95be94981aa820730132ac68f8f8841/Sources/OgiCore/Signals.swift#L49-L51) |
| FineTune | Bundle-ID prefixes `com.apple.corespeech` / `com.apple.CoreSpeech` and process name `corespeech`, among other system daemons (mixer list) | [AudioProcessMonitor.swift#L20-L57](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Monitors/AudioProcessMonitor.swift#L20-L57) |

**What the measurements say:**

- Parrot: "Siri joins whenever any app opens the mic, Parrot's own recording included, so a call could never 'end'". This bears on Carbon's own auto-stop.
- Ogi: CoreSpeech reports input "continuously" while `DeviceIsRunningSomewhere` reports idle. It keeps the per-process read anyway, because "the device property … always reports false for Bluetooth microphones (an Apple bug)". That Bluetooth claim is unverified.
- FlyOnTheWall, measured on macOS 26.3: CoreSpeech reported `IsRunningInput = true` on an idle Mac, then the flag disappeared minutes later ([activity.rs#L25-L39](https://github.com/nolanmak/FlyOnTheWall/blob/357fa595a8c3bf033359d2c759465071d08d9447/crates/fotw-audio/src/platform/macos/activity.rs#L25-L39)).

**Other strategies:**

- pasrom and Omi use **allowlists** of call apps, so CoreSpeech never matches. pasrom logs unmatched input holders ([MicInputDetector.swift#L152-L154](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/MicInputDetector.swift#L152-L154)).
- Hyprnote's denylist has no Apple daemons ([policy.rs#L30-L83](https://github.com/fastrepl/anarlog/blob/7165aba8974c2c3ff4cfda34846027b4e0e1d7a9/plugins/detect/src/policy.rs#L30-L83)). Its 15 s hold threshold would still filter 1–7 s bursts **(inference)**.

**Caveat on spelling.** Some lists spell the ID in lowercase (FineTune, and the small Parfait and Nutola detectors). Compare bundle IDs case-insensitively.

## Recommendations: what changes in the proposed v1 rule

The proposed rule, for reference:

- Tap every audio process whose responsible app is the Provider, and rebuild the tap when processes appear.
- Fall back to a global tap that excludes Carbon.
- If there are no callbacks for 5 s, rebuild, then fall back.
- Treat full-rate zeros as normal silence.
- Check the permission upfront instead of inferring it from audio.

The changes:

1. **Keep responsible-app grouping, and add two guards.**
   - Apply it only when the Provider's main process is its own responsible party (pasrom). Otherwise use the outermost `.app` executable path, which is FreeAudio's chain.
   - Test from the signed `.app`, not a terminal, because a shell-launched probe's responsible process is the terminal.
   - **(inference)** Responsibility groups by app, not by tab. A second Chrome or Safari tab playing media goes to the same audio or GPU helper and lands in the Them track. Accept this for v1 and note it.
2. **"Rebuilt when processes appear": update the description instead of rebuilding.**
   - Listen to `kAudioHardwarePropertyProcessObjectList`.
   - Set `kAudioTapPropertyDescription` on the running tap. The header allows it, and FreeAudio measured ~7 ms with no gap.
   - Never cache process object IDs, because they are reused.
   - Do not rely on `bundleIDs` and `processRestoreEnabled` for helpers. Restore works by exact bundle ID, and helper-ID matching is unproven.
3. **Change "no callbacks for 5 s → rebuild, then fall back". As written, it would fire wrongly.**
   - With `TapAutoStart`, no callbacks is the documented state until a tapped process plays. A Provider that has not opened an output stream yet (lobby, pre-join) would be pushed to the global tap.
   - Fire the check only when a process owned by the Provider reports `IsRunningOutput`:
     - if that process is not in the tap, update the description;
     - if it is in the tap and there are still no callbacks after 5 s, rebuild, then fall back.
   - After the first callback the check can never fire again, because a dead tap shows full-rate zeros (forum 825780). So also re-run the ownership diff whenever the process list changes.
4. **"Full-rate zeros = normal silence" holds, and should stay.** Apple, Meetily, pasrom and Run 1 agree that zeros alone are not a fault signal. Because of that, the permission check must be explicit (next point).
5. **"Permission checked upfront" has no public API.** The choices:
   - `TCCAccessPreflight("kTCCServiceAudioCapture")` through `dlopen`, as AudioCap, FineTune, Hyprnote and FreeAudio do: `0` = granted, `1` = denied, `2` = never asked. It is private and fine for Developer ID distribution.
   - The unverified public-API signal: setting `kAudioTapPropertyDescription` returns `kAudioDevicePermissionsError` when the permission is denied. Worth one probe run, because it would avoid the private API.

   Re-check on app activation, as AudioCap does, because the user can revoke the grant at any time.
6. **Detection:**
   - Ignore `com.apple.CoreSpeech` (case-insensitive) and Carbon itself.
   - Prefer matching *to the Provider*, as an allowlist, over a denylist.
   - Do not count CoreSpeech's input when deciding that a Meeting ended. Parrot found that CoreSpeech joins whenever any app opens the mic, Carbon's own recording included.
