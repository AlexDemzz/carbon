# Power assertions as a Detection signal

Researched 2026-10-27 for [ticket 17](../../.scratch/carbon-v1/issues/17-power-assertions-as-detection-signal.md). The question is whether Detection should read macOS power assertions next to mic-in-use and EventKit. Section 1 of [prior-art-minute-meeting-transcriber.md](prior-art-minute-meeting-transcriber.md) already covers pasrom's `PowerAssertionDetector` rules (Teams "call in progress", Zoom display-sleep type, Webex "On a call", Chromium "WebRTC has active PeerConnections", 2 × 3 s confirm, 15 s end grace, 5 s cooldown) and Minute's silence auto-stop. This note does not repeat them. It covers what that note left open:

- the Apple API itself;
- where the browser assertions come from in Chromium, WebKit and Firefox;
- what native apps are known to hold;
- the detection rules of Hyprnote and OpenOats;
- pasrom's mic list, cap and manual-start handling.

Each claim links to a file and line range at a pinned commit. Anything I concluded myself, rather than read in source or measured, is marked **(inference)**. "Measured" means I ran it on this Mac (macOS 27.0.1, Xcode 26.4 SDK).

## Sources and pins

| Source | Pin | What it is |
|---|---|---|
| macOS SDK `IOKit.framework/Headers/pwr_mgt/IOPMLib.h` | Xcode 26.4 (MacOSX.sdk) | Public header |
| [apple-oss-distributions/IOKitUser](https://github.com/apple-oss-distributions/IOKitUser/tree/323ead896d04424f87184d8f6ff0cce811aab106) | `323ead8` (2026-04-17) | Client side of the IOPM API, including the private header |
| [apple-oss-distributions/PowerManagement](https://github.com/apple-oss-distributions/PowerManagement/tree/d415e45501842834a280930c3eed9186544a67f0) | `d415e45` (2025-10-16) | `powerd` server and `pmset` |
| [chromium/chromium](https://github.com/chromium/chromium/tree/2fc1d860a6db11710202e674c0446c2e5296c6c9) | `2fc1d86` (2026-10-27) | Chromium, the content layer shared by Chrome, Edge, Arc, Brave and Electron |
| [WebKit/WebKit](https://github.com/WebKit/WebKit/tree/21a41d911944b465732e2d41e14503f18c8d05c8) | `21a41d9` | Safari's engine |
| [mozilla-firefox/firefox](https://github.com/mozilla-firefox/firefox/tree/ff3b300c151f45f09f300284659f24f5d95b0f25) | `ff3b300` | Firefox |
| [pasrom/meeting-transcriber](https://github.com/pasrom/meeting-transcriber/tree/1765408a99b4c1360735648df7f41055e647f4a5) | `1765408` (same pin as the prior-art note) | Plus its issues #84, #562, #563, #608, #652, #765 |
| [fastrepl/anarlog](https://github.com/fastrepl/anarlog/tree/abe1516fc3331ca8ef39bd92955090499d438165) ("Hyprnote") | `abe1516` (2026-10-28) | Hyprnote, renamed Anarlog. Tauri app with a Rust `detect` crate and plugin |
| [yazinsai/OpenOats](https://github.com/yazinsai/OpenOats/tree/b27bf0156bf47cbca4d2adbee7a4a14fb7f0e410) | `b27bf01` | Formerly OpenGranola. Swift app |
| [Zackriya-Solutions/meetily](https://github.com/Zackriya-Solutions/meetily/tree/a2cb62e827da7ef59f65064c97233efb2313878e) | `a2cb62e` (2026-09-10) | Meetily |

Link prefixes used below:
- **IK** = `https://github.com/apple-oss-distributions/IOKitUser/blob/323ead896d04424f87184d8f6ff0cce811aab106/`
- **PM** = `https://github.com/apple-oss-distributions/PowerManagement/blob/d415e45501842834a280930c3eed9186544a67f0/`
- **CR** = `https://github.com/chromium/chromium/blob/2fc1d860a6db11710202e674c0446c2e5296c6c9/`
- **WK** = `https://github.com/WebKit/WebKit/blob/21a41d911944b465732e2d41e14503f18c8d05c8/`
- **FF** = `https://github.com/mozilla-firefox/firefox/blob/ff3b300c151f45f09f300284659f24f5d95b0f25/`
- **P** = `https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/`
- **H** = `https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/`
- **O** = `https://github.com/yazinsai/OpenOats/blob/b27bf0156bf47cbca4d2adbee7a4a14fb7f0e410/`

## Summary

| Question | Answer |
|---|---|
| Is `IOPMCopyAssertionsByProcess` public? | **Yes.** It is in the public SDK header, available since macOS 10.7, not deprecated, and has an Apple reference page. Neither the client nor `powerd` checks any entitlement or privilege for it, and the App Sandbox profile allows the `powerd` lookup. |
| What it returns | `{pid: [assertion dict]}`. Measured keys: `AssertName`, `AssertType`, `AssertPID`, `Process Name`, `AssertStartWhen`, `AssertionId`, `GlobalUniqueID`, `AssertLevel`, `AssertionTrueType`, plus optional `Details`, `HumanReadableReason`, `TimeoutSeconds`. |
| Cost | One Mach round trip to `powerd`. Measured **≈ 0.11 ms per call** (8 processes holding assertions). |
| Push alternative | Only private: `IOPMAssertionNotify()` + `notify_register("com.apple.system.powermanagement.assertions.anychange")`. `powerd` refuses it for non-admin users. **Poll instead.** |
| Chromium | `content/browser/webrtc/webrtc_internals.cc`, held by the **browser process** for **any** PeerConnection whose ICE state is `checking`/`connected`/`completed`. Media is not checked, so a data-channel-only connection counts too. Type `NoIdleSleepAssertion` (= PreventUserIdleSystemSleep). It is created in `BrowserMainLoop`, so every content embedder has it: Chrome, Edge, Arc, Brave, Electron. |
| Safari / WebKit | **No WebRTC-specific assertion.** Only "com.apple.WebCore: HTMLMediaElement playback" (display sleep, for video with audio or a remote MediaStream video) and the RunningBoard "WebKit Media Playback" assertion, which YouTube triggers just like a call. |
| Firefox | **No WebRTC-specific assertion.** Only the wake-lock topics `video-playing` (any MediaStream video), `audio-playing` and `screen`. |
| Native apps | Zoom `NoDisplaySleepAssertion` "Describe Activity Type"; Teams "call in progress" plus an idle "Video Wake Lock"; Webex "On a call" + "io avilable". Slack, Discord and the Meet PWA have no measurement in any source. **No prior art measures Zoom between back-to-back calls.** pasrom #765 reports two back-to-back **Teams** calls merged into one transcript. |
| Prior-art rules | Hyprnote: per-process mic ≥ **15 s** → a notification **asking**. It has a 40-bundle ignore list in 6 categories, a 10 min per-app cooldown, auto-stop on mic release after 5 s plus an AX check, and calendar auto-start for events with a link (on by default). OpenOats: device mic 5 s + a known meeting app running, or the camera → asks (auto-record is opt-in), with a 15 min silence stop. Meetily: no auto-detection. |

## 1. The Apple API

### Public, documented, no entitlement

- **Declared in the public SDK**, with no deprecation macro: `IOReturn IOPMCopyAssertionsByProcess(CFDictionaryRef *AssertionsByPID) __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_3_2)`. The header text: "Returns a dictionary listing all assertions, grouped by their owning process … keys to the CFDictionary are pids stored as CFNumbers … The value associated with each CFNumber pid is a CFArray of active assertions" (`IOPMLib.h` L694-L711 in the Xcode 26.4 SDK). Apple's reference page is [documentation/iokit/1557130-iopmcopyassertionsbyprocess](https://developer.apple.com/documentation/iokit/1557130-iopmcopyassertionsbyprocess), listed among the IOPMLib.h symbols in Apple's documentation index.
- **Key names.** The public keys are `kIOPMAssertionNameKey` = `"AssertName"` and `kIOPMAssertionTypeKey` = `"AssertType"` (`IOPMLib.h` L875, L984). The PID key is only in the private header: `kIOPMAssertionPIDKey` = `"AssertPID"` ([IK pwr_mgt.subproj/IOPMLibPrivate.h#L623-L631](https://github.com/apple-oss-distributions/IOKitUser/blob/323ead896d04424f87184d8f6ff0cce811aab106/pwr_mgt.subproj/IOPMLibPrivate.h#L623-L631)). The public API does not need it, because the outer dictionary is already keyed by PID.
- **Measured keys on macOS 27.0.1:** `AssertName`, `AssertType`, `AssertPID`, `Process Name`, `AssertStartWhen`, `AssertionId`, `GlobalUniqueID`, `AssertLevel` and `AssertionTrueType` on every entry. `Details`, `HumanReadableReason`, `BundlePath`, `TimeoutSeconds` and `TimeoutAction` appear when the creator sets them.
- **Legacy type names are reported as created.** Chromium creates `kIOPMAssertionTypeNoIdleSleep`/`NoDisplaySleep` ("Deprecated in 10.7", `IOPMLib.h` L1026-L1037), and pmset shows them as `NoDisplaySleepAssertion`. Measured: Orca, an Electron app, holds `NoDisplaySleepAssertion named: "Video Wake Lock"`. A type match must accept both spellings, as pasrom does.
- **Assertions made on another process's behalf.** `AssertionOnBehalfOfPID` exists, but it is "purely for accounting & debugging" ([IK IOPMLibPrivate.h#L876-L884](https://github.com/apple-oss-distributions/IOKitUser/blob/323ead896d04424f87184d8f6ff0cce811aab106/pwr_mgt.subproj/IOPMLibPrivate.h#L876-L884)). This is how `coreaudiod` shows "Created for PID" in pasrom #563 (below).
- **No privilege check anywhere on the path.**
  - The client sends a MIG request to `powerd` (`com.apple.PowerManagement.control`) and rebuilds the PID-keyed dictionary locally ([IK pwr_mgt.subproj/IOPMAssertions.c#L3207-L3221](https://github.com/apple-oss-distributions/IOKitUser/blob/323ead896d04424f87184d8f6ff0cce811aab106/pwr_mgt.subproj/IOPMAssertions.c#L3207-L3221), [#L3291-L3294](https://github.com/apple-oss-distributions/IOKitUser/blob/323ead896d04424f87184d8f6ff0cce811aab106/pwr_mgt.subproj/IOPMAssertions.c#L3291-L3294)).
  - The server answers `kIOPMAssertionMIGCopyAll` without checking an entitlement or the caller's UID ([PM pmconfigd/PMAssertions.c#L1242-L1264](https://github.com/apple-oss-distributions/PowerManagement/blob/d415e45501842834a280930c3eed9186544a67f0/pmconfigd/PMAssertions.c#L1242-L1264)).
- **Sandbox.** `/System/Library/Sandbox/Profiles/application.sb` (the App Sandbox base profile on this Mac) applies `(power-assertions)` unconditionally (L757). `appsandbox-common.sb` defines that rule as `allow mach-lookup` of `com.apple.PowerManagement.control` and `com.apple.iokit.powerdxpc` (L672-L676). A sandboxed app can therefore call it without an entitlement. That backs pasrom's "sandbox-safe, no entitlement needed" comment, which the prior-art note quotes. The profile was read on macOS 27.0.1. That macOS 26 ships the same rule is an **(inference)**. For Carbon, which is not sandboxed, the question does not arise.

### Polling cost and the private notification

- **Polling is cheap.** Measured: 200 calls averaged **113 µs each** with 8 processes holding assertions. At a 3 s poll that is about 0.004 % of one core **(inference, arithmetic)**. The call is a synchronous Mach message, so it belongs off the main thread **(inference)**.
- **A push notification exists, but it is private and admin-only:**
  - The private header defines `kIOPMAssertionsAnyChangedNotifyString` = `"com.apple.system.powermanagement.assertions.anychange"`: "Fires when any individual assertion is created, released, or modified. Caller has to call IOPMAssertionNotify() and register with powerd with this string before calling notify_register" ([IK IOPMLibPrivate.h#L971-L991](https://github.com/apple-oss-distributions/IOKitUser/blob/323ead896d04424f87184d8f6ff0cce811aab106/pwr_mgt.subproj/IOPMLibPrivate.h#L971-L991)).
  - `IOPMAssertionNotify(char *name, int req_type)` is declared only in the private header ([IK IOPMLibPrivate.h#L3726-L3736](https://github.com/apple-oss-distributions/IOKitUser/blob/323ead896d04424f87184d8f6ff0cce811aab106/pwr_mgt.subproj/IOPMLibPrivate.h#L3726-L3736)). The SDK's `IOKit.tbd` exports `_IOPMAssertionNotify` (measured), so the symbol links, but no public header declares it.
  - `powerd` only posts `anychange` while at least one process has registered (`if (gAnyChange) notify_post(...)`, [PM PMAssertions.c#L4333](https://github.com/apple-oss-distributions/PowerManagement/blob/d415e45501842834a280930c3eed9186544a67f0/pmconfigd/PMAssertions.c#L4333)).
  - Registering requires root or an admin user: `if ( !(callerIsRoot(callerUID) || callerIsAdmin(callerUID, callerGID))) *return_code = kIOReturnNotPrivileged` ([PM PMAssertions.c#L3992-L4011](https://github.com/apple-oss-distributions/PowerManagement/blob/d415e45501842834a280930c3eed9186544a67f0/pmconfigd/PMAssertions.c#L3992-L4011)).
  - `pmset -g assertionslog` uses exactly this pair ([PM pmset/pmset.m#L3255-L3275](https://github.com/apple-oss-distributions/PowerManagement/blob/d415e45501842834a280930c3eed9186544a67f0/pmset/pmset.m#L3255-L3275)).
  - Measured as an admin user: `IOPMAssertionNotify(anychange, kIOPMNotifyRegister)` returned `kIOReturnSuccess`.
- **So: poll.** The notification would save about 0.1 ms every 3 s. It costs a private symbol and fails for standard users, so it is not worth it **(inference)**.

## 2. Chromium: "WebRTC has active PeerConnections"

- **Where.** `WebRTCInternals::GetWakeLock()` asks the device service for `WakeLockType::kPreventAppSuspension`, `WakeLockReason::kOther`, `"WebRTC has active PeerConnections"` ([CR content/browser/webrtc/webrtc_internals.cc#L927-L940](https://github.com/chromium/chromium/blob/2fc1d860a6db11710202e674c0446c2e5296c6c9/content/browser/webrtc/webrtc_internals.cc#L927-L940)). On macOS, `kPreventAppSuspension` becomes `IOPMAssertionCreateWithName(kIOPMAssertionTypeNoIdleSleep, …)` ([CR services/device/wake_lock/power_save_blocker/power_save_blocker_mac.cc#L73-L89](https://github.com/chromium/chromium/blob/2fc1d860a6db11710202e674c0446c2e5296c6c9/services/device/wake_lock/power_save_blocker/power_save_blocker_mac.cc#L73-L89)). The type is therefore `NoIdleSleepAssertion`, the legacy alias of PreventUserIdleSystemSleep. It is not a display-sleep type.
- **When it is taken and released:**
  - A PeerConnection counts as connected when `oniceconnectionstatechange` reports `"connected"`, `"checking"` or `"completed"`. It stops counting on `"failed"`, `"disconnected"`, `"closed"` or `"new"`, or on `close` ([CR webrtc_internals.cc#L263-L272](https://github.com/chromium/chromium/blob/2fc1d860a6db11710202e674c0446c2e5296c6c9/content/browser/webrtc/webrtc_internals.cc#L263-L272)).
  - A single counter covers the whole browser, all tabs and frames included. The lock is requested when the count goes above 0 and cancelled at 0 ([CR #L881-L925](https://github.com/chromium/chromium/blob/2fc1d860a6db11710202e674c0446c2e5296c6c9/content/browser/webrtc/webrtc_internals.cc#L881-L925)).
  - **Any PeerConnection counts, whatever it carries.** The code looks at ICE state only, never at tracks, so a data-channel-only connection or an audio-only call takes the lock too **(inference, from the code path)**.
  - `"checking"` counts as well, so the lock appears before media flows. pasrom saw this in the field: "Google Meet raises the same WebRTC assertion on a page you cannot even join" ([P WatchLoop+Consent.swift#L10-L16](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/WatchLoop+Consent.swift#L10-L16)).
- **Which apps get it.**
  - The default constructor enables power-save blocking (`WebRTCInternals(500, true)`, [CR #L120-L134](https://github.com/chromium/chromium/blob/2fc1d860a6db11710202e674c0446c2e5296c6c9/content/browser/webrtc/webrtc_internals.cc#L120-L134)).
  - The singleton is created unconditionally in `BrowserMainLoop` ([CR content/browser/browser_main_loop.cc#L1494](https://github.com/chromium/chromium/blob/2fc1d860a6db11710202e674c0446c2e5296c6c9/content/browser/browser_main_loop.cc#L1494)), i.e. in the content layer, not in `chrome/`. Every content embedder therefore inherits it: Chrome, Edge, Arc, Brave, Vivaldi, Opera, and Electron apps (Slack, Discord, WhatsApp, Teams' WebView) **(inference: same content layer; not measured per app)**.
  - The assertion is listed under the app's **main process name** ("Google Chrome", "Brave Browser", "Slack"), not under a helper. Measured for a related Chromium wake lock: Orca's "Video Wake Lock" is listed under `Orca`, its main Electron process. pasrom keys its browser identity on that same name ([P MeetingPatterns.swift#L101-L120](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/MeetingPatterns.swift#L101-L120)).
- **Gaps:**
  - **Slack huddles:** not measured by anyone. pasrom #608 asks for Slack and has no data. If huddles use an in-renderer RTCPeerConnection, process "Slack" will hold the WebRTC assertion **(inference)**.
  - **Discord** voice is widely reported to run in a native voice module rather than Chromium's PeerConnection, so it may never take the assertion. **Unverified.**
  - **Google Meet PWA:** the bundle is a Chrome app shim (`com.google.Chrome.app.kjgfgldnnfobanmcafgkdilakhehfkbm`, [O MeetingDetector.swift#L476](https://github.com/yazinsai/OpenOats/blob/b27bf0156bf47cbca4d2adbee7a4a14fb7f0e410/OpenOats/Sources/OpenOats/Meeting/MeetingDetector.swift#L476)). The PeerConnection lives in Chrome's renderer, so the assertion should be listed under "Google Chrome", not under the shim **(inference)**.
- **Other Chromium locks that are not calls:**
  - "Video Wake Lock" (`kPreventDisplaySleep`): held while a visible video with frames is playing, or a MediaStream video of any size, self-view included ([CR third_party/blink/renderer/core/html/media/video_wake_lock.cc#L142-L178](https://github.com/chromium/chromium/blob/2fc1d860a6db11710202e674c0446c2e5296c6c9/third_party/blink/renderer/core/html/media/video_wake_lock.cc#L142-L178), [#L193-L197](https://github.com/chromium/chromium/blob/2fc1d860a6db11710202e674c0446c2e5296c6c9/third_party/blink/renderer/core/html/media/video_wake_lock.cc#L193-L197)).
  - "Playing audio" (`kPreventAppSuspension`) ([CR content/browser/media/media_web_contents_observer.cc#L709-L722](https://github.com/chromium/chromium/blob/2fc1d860a6db11710202e674c0446c2e5296c6c9/content/browser/media/media_web_contents_observer.cc#L709-L722)).
  - This is why pasrom matches the WebRTC name and never the type, and why Teams' idle WebView "Video Wake Lock" is not call evidence (prior-art note). The string also shows that Teams' WebView is Chromium-based **(inference)**.

## 3. Safari and Firefox

### WebKit: playback assertions only

- WebKit has one Mac IOPM creator, `SleepDisablerCocoa`. It takes `PreventUserIdleDisplaySleep` or `PreventUserIdleSystemSleep` with a caller-supplied reason ([WK Source/WebCore/PAL/pal/system/cocoa/SleepDisablerCocoa.cpp#L41-L76](https://github.com/WebKit/WebKit/blob/21a41d911944b465732e2d41e14503f18c8d05c8/Source/WebCore/PAL/pal/system/cocoa/SleepDisablerCocoa.cpp#L41-L76)). Its callers:
  - `HTMLMediaElement`, reason **"com.apple.WebCore: HTMLMediaElement playback"** ([WK Source/WebCore/html/HTMLMediaElement.cpp#L8903-L8912](https://github.com/WebKit/WebKit/blob/21a41d911944b465732e2d41e14503f18c8d05c8/Source/WebCore/html/HTMLMediaElement.cpp#L8903-L8912)). It applies only when playback progresses and the element is video+audio or has a **remote MediaStream video track**. Audio-only elements are allowed to sleep ([#L8926-L8963](https://github.com/WebKit/WebKit/blob/21a41d911944b465732e2d41e14503f18c8d05c8/Source/WebCore/html/HTMLMediaElement.cpp#L8926-L8963)). An audio-only Meet call in Safari therefore takes no IOPM assertion from WebKit **(inference)**, while a YouTube video takes the same one as a video call.
  - The Screen Wake Lock API, reason "Screen Wake Lock" ([WK Source/WebCore/Modules/screen-wake-lock/WakeLockManager.cpp#L73](https://github.com/WebKit/WebKit/blob/21a41d911944b465732e2d41e14503f18c8d05c8/Source/WebCore/Modules/screen-wake-lock/WakeLockManager.cpp#L73)).
  - Web-process sleep disablers are recreated in the UI process ([WK Source/WebKit/UIProcess/WebPageProxy.cpp#L20909-L20914](https://github.com/WebKit/WebKit/blob/21a41d911944b465732e2d41e14503f18c8d05c8/Source/WebKit/UIProcess/WebPageProxy.cpp#L20909-L20914)), so they are listed under Safari.
- The **"WebKit Media Playback"** RunningBoard assertion is taken whenever any page is audible, a call or anything else ([WK Source/WebKit/UIProcess/WebProcessProxy.cpp#L2623-L2628](https://github.com/WebKit/WebKit/blob/21a41d911944b465732e2d41e14503f18c8d05c8/Source/WebKit/UIProcess/WebProcessProxy.cpp#L2623-L2628), [WebProcessPool.cpp#L2945-L2953](https://github.com/WebKit/WebKit/blob/21a41d911944b465732e2d41e14503f18c8d05c8/Source/WebKit/UIProcess/WebProcessPool.cpp#L2945-L2953)).
- A GitHub code search of WebKit for `IOPMAssertionCreateWithDescription`/`WithName` finds only `SleepDisablerCocoa`, an SPI header and test tooling. **WebKit has no WebRTC assertion.**
- **Field data (pasrom #563, macOS 26.5.2, Safari 26):** "Safari's `runningboardd` assertion is `WebKit Media Playback` for both cases \[call and YouTube], so it is genuinely useless". During a Meet call, `coreaudiod` holds `PreventUserIdleSystemSleep` named `com.apple.audio.VPAUAggregateAudioDevice-….context.preventuseridlesleep`, "Created for PID" of the WebKit helper, with `Resources: audio-in audio-out`. YouTube alone gives `BuiltInSpeakerDevice` with `audio-out` only. The mic owner is `com.apple.WebKit.GPU`, which `responsibility_get_pid_responsible_for_pid` maps to Safari ([issue #563](https://github.com/pasrom/meeting-transcriber/issues/563)). pasrom's maintainer agrees that Core Audio mic-in-use is the better mechanism. He has not wired Safari to it, because "Safari holds the mic for dictation, voice search and voice messages too" (same thread, 2026-08-01). pasrom's own code also records that a FaceTime link opened in a browser "is owned by `com.apple.WebKit.GPU`" ([P MicInputDetector.swift#L66-L80](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/MicInputDetector.swift#L66-L80)).

### Firefox: media wake locks only

- Firefox has one Mac creator, `MacWakeLockListener`. It maps the topics `screen` and `video-playing` to `NoDisplaySleepAssertion`, and `audio-playing` and `download-in-progress` to `NoIdleSleepAssertion`, **named after the topic string** ([FF widget/cocoa/nsAppShell.mm#L65-L146](https://github.com/mozilla-firefox/firefox/blob/ff3b300c151f45f09f300284659f24f5d95b0f25/widget/cocoa/nsAppShell.mm#L65-L146)).
- `video-playing` is requested for any video with audio, or **any MediaStream video**: "Some web conferencing sites route audio outside the video element, and would not be detected unless we check for media stream" ([FF dom/media/mediaelement/HTMLVideoElement.cpp#L501-L531](https://github.com/mozilla-firefox/firefox/blob/ff3b300c151f45f09f300284659f24f5d95b0f25/dom/media/mediaelement/HTMLVideoElement.cpp#L501-L531)). `audio-playing` comes from audible media elements and WebAudio ([FF HTMLMediaElement.cpp#L5519](https://github.com/mozilla-firefox/firefox/blob/ff3b300c151f45f09f300284659f24f5d95b0f25/dom/media/mediaelement/HTMLMediaElement.cpp#L5519), [FF dom/media/webaudio/AudioDestinationNode.cpp#L783](https://github.com/mozilla-firefox/firefox/blob/ff3b300c151f45f09f300284659f24f5d95b0f25/dom/media/webaudio/AudioDestinationNode.cpp#L783)).
- A GitHub code search of Firefox for `IOPMAssertionCreateWithName` finds only `nsAppShell.mm`. **Firefox has no WebRTC assertion.**

**Consequence:** browser Meetings in Safari and Firefox are visible only through mic-in-use. In Safari the mic holder is `com.apple.WebKit.GPU`, not `com.apple.Safari`.

## 4. What native apps hold

| App | Assertion (name / type) | Source | Idle behaviour |
|---|---|---|---|
| Zoom (`zoom.us`) | "Describe Activity Type" / `NoDisplaySleepAssertion`, Apple's documentation placeholder shipped as the name | [pasrom #562](https://github.com/pasrom/meeting-transcriber/issues/562) (macOS 26.5.2, Zoom 6.x) | Not reported. **No source measures whether it is dropped between back-to-back calls.** |
| Teams (`MSTeams`, `Microsoft Teams WebView`, bundle `com.microsoft.teams2`) | "call in progress"; the WebView holds a display-sleep "Video Wake Lock" while idle | prior-art note; bundle and process from [pasrom #84](https://github.com/pasrom/meeting-transcriber/issues/84) | **Back-to-back Teams calls merged** into one transcript on 0.8.1 / macOS 27.0.1 ([pasrom #765](https://github.com/pasrom/meeting-transcriber/issues/765), open, no logs) |
| Webex | "On a call" / `PreventUserIdleDisplaySleep` + "io avilable" (sic) / `PreventUserIdleSystemSleep` | [pasrom #652](https://github.com/pasrom/meeting-transcriber/issues/652) (Webex 46.7) | "no assertion owned by Webex" while idle |
| FaceTime | None known. The mic is owned by `com.apple.avconferenced` | [P MicInputDetector.swift#L66-L80](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/MicInputDetector.swift#L66-L80) | n/a. Hyprnote also treats `com.apple.TelephonyUtilities` / `.callservicesd` as "iPhone Call" ([H crates/detect/src/list/macos.rs#L11-L16](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/crates/detect/src/list/macos.rs#L11-L16)) |
| Slack huddles, Discord, Meet PWA | **No measurement in any source.** Expected: Chromium WebRTC under "Slack" / "Google Chrome"; Discord unknown (§2) | — | — |

pasrom #652 also states the structural risk: "detection depends on vendor-controlled assertion strings that may change". Zoom (#562) and Webex (#652) each broke pasrom's detection once.

## 5. Detection rules in other prior art

### Hyprnote (fastrepl/anarlog)

- **Signal.** A Core Audio listener on `DeviceIsRunningSomewhere` triggers a scan. A 1 s poll serves as fallback ([H crates/detect/src/mic/macos/mod.rs#L15-L21](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/crates/detect/src/mic/macos/mod.rs#L15-L21)).
- **Process resolution.** It lists per-process `is_running_input` and resolves each PID to its **outermost `.app` bundle**, so a Chrome Helper counts as Chrome ([H crates/detect/src/list/macos.rs#L84-L106](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/crates/detect/src/list/macos.rs#L84-L106), [#L184-L212](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/crates/detect/src/list/macos.rs#L184-L212), [#L272-L290](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/crates/detect/src/list/macos.rs#L272-L290)).
- **No power assertions.**
- **Threshold.** The mic must stay held **15 s** (`DEFAULT_MIC_ACTIVE_THRESHOLD_SECS = 15`, user-settable). After it fires, the app gets a **10 min cooldown** ([H plugins/detect/src/mic_usage_tracker.rs#L8-L9](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/plugins/detect/src/mic_usage_tracker.rs#L8-L9), [#L60-L101](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/plugins/detect/src/mic_usage_tracker.rs#L60-L101)). A mic stop before 15 s cancels the timer ([H plugins/detect/src/handler.rs#L58-L107](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/plugins/detect/src/handler.rs#L58-L107)).
- **Mic alone only asks.** `micDetected` shows a "Yes" notification with a **15 s timeout**, titled after the nearest calendar event within ±15 min. The footer offers to ignore the app ([H apps/desktop/src/stt/detect-events.ts#L414-L503](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/apps/desktop/src/stt/detect-events.ts#L414-L503)).
- **Ignore list: 40 bundle IDs in 6 categories, all ignored by default** ([H plugins/detect/src/policy.rs#L19-L111](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/plugins/detect/src/policy.rs#L19-L111), default at [#L196-L200](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/plugins/detect/src/policy.rs#L196-L200)). A user's include overrides a category ignore, and a user's ignore overrides everything ([#L132-L140](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/plugins/detect/src/policy.rs#L132-L140)).
  - Dictation: `com.electron.wispr-flow`, `com.seewillow.WillowMac`, `com.superduper.superwhisper`, `com.prakashjoshipax.VoiceInk`, `com.goodsnooze.macwhisper`, `com.descript.beachcube`, `com.apple.VoiceMemos`, `com.electron.aqua-voice`.
  - IDE: `dev.warp.Warp-Stable`, `com.exafunction.windsurf`, `com.microsoft.VSCode`, `com.todesktop.230313mzl4w4u92` (Cursor).
  - Screen recording: `so.cap.desktop`, `so.cap.desktop.dev`, `com.timpler.screenstudio`, `com.loom.desktop`, `com.obsproject.obs-studio`, `pl.maketheweb.cleanshotx`, `com.getcleanshot.app-setapp`, `com.wulkano.kap`, `com.wulkano.kap.helper`, `net.telestream.screenflow10`, `com.techsmith.camtasia`, `com.techsmith.camtasia2024`, `com.TechSmith.Snagit`, `com.TechSmith.Snagit2024`, `com.apple.QuickTimePlayerX`, `com.apple.screenshot.launcher`.
  - AI assistants: `com.openai.chat`, `com.openai.codex`, `com.anthropic.claudefordesktop`.
  - Other: `com.raycast.macos`, `com.apple.garageband10`, `com.apple.Sound-Settings.extension`.
  - Self: four `com.hyprnote.*` IDs.
  - It ignores **no Apple speech daemon**: the source has no `CoreSpeech`, `corespeechd` or Siri ID.
- **Meeting-capable apps** (used for auto-stop and calendar logic, not for starting): 30 browser bundle IDs ([H apps/desktop/src/stt/meeting-apps.ts#L7-L45](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/apps/desktop/src/stt/meeting-apps.ts#L7-L45)) plus FaceTime/avconferenced, Zoom `us.zoom.xos`, Teams `com.microsoft.teams`/`teams2`, Webex, Slack `com.slack.Slack`/`com.tinyspeck.slackmacgap`, KakaoTalk, WhatsApp, Discord `com.hnc.Discord`, Signal, Telegram, LINE, Messenger ([#L192-L306](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/apps/desktop/src/stt/meeting-apps.ts#L192-L306), [#L387-L389](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/apps/desktop/src/stt/meeting-apps.ts#L387-L389)).
- **Calendar auto-start, without asking, on by default** (`auto_start_scheduled_meetings: true`, [H apps/desktop/src/settings/schema.ts#L73-L77](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/apps/desktop/src/settings/schema.ts#L73-L77)):
  - Only non-all-day events **with a meeting link** qualify: "Calendar blocks without a meeting link ('Lunch', 'Focus time') are excluded: auto-start watches every calendar, so anything looser would record all day" ([H apps/desktop/src/stt/scheduled-auto-start.tsx#L40-L57](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/apps/desktop/src/stt/scheduled-auto-start.tsx#L40-L57)).
  - Recording starts at the event start, with a 5 min grace ([#L24-L38](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/apps/desktop/src/stt/scheduled-auto-start.tsx#L24-L38), [#L86-L126](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/apps/desktop/src/stt/scheduled-auto-start.tsx#L86-L126)).
  - **Back-to-back rule:** a meeting app that has held the mic for ≥ 10 min before this event's start, since during another event, "is still on an earlier call". An early join counts only within 5 min of the start ([#L150-L189](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/apps/desktop/src/stt/scheduled-auto-start.tsx#L150-L189)).
- **Auto-stop** (on by default, [schema.ts#L62-L66](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/apps/desktop/src/settings/schema.ts#L62-L66)) starts when the trigger app releases the mic ([H detect-events.ts#L504-L538](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/apps/desktop/src/stt/detect-events.ts#L504-L538)). After a **5 s** confirm delay:
  - an Accessibility inspection of the meeting UI can veto the stop;
  - **browsers prompt** instead of stopping;
  - a network drop holds the recording until event end + 10 min, or else 8 min;
  - KakaoTalk is marked unreliable for auto-stop ([H apps/desktop/src/stt/auto-stop.ts#L19-L46](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/apps/desktop/src/stt/auto-stop.ts#L19-L46), [#L48-L90](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/apps/desktop/src/stt/auto-stop.ts#L48-L90); flow at [detect-events.ts#L300-L397](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/apps/desktop/src/stt/detect-events.ts#L300-L397)).
  - System sleep stops the recording immediately ([detect-events.ts#L539-L543](https://github.com/fastrepl/anarlog/blob/abe1516fc3331ca8ef39bd92955090499d438165/apps/desktop/src/stt/detect-events.ts#L539-L543)).

### OpenOats (formerly OpenGranola)

- **Start:**
  - The **device-level** `DeviceIsRunningSomewhere` on any input device must hold for 5 s.
  - A known meeting app must then be **running**; it does not have to hold the mic. Alternatively, the camera turning on starts detection directly, with 3 s of hysteresis on camera off ([O OpenOats/Sources/OpenOats/Meeting/MeetingDetector.swift#L220-L221](https://github.com/yazinsai/OpenOats/blob/b27bf0156bf47cbca4d2adbee7a4a14fb7f0e410/OpenOats/Sources/OpenOats/Meeting/MeetingDetector.swift#L220-L221), [#L309-L392](https://github.com/yazinsai/OpenOats/blob/b27bf0156bf47cbca4d2adbee7a4a14fb7f0e410/OpenOats/Sources/OpenOats/Meeting/MeetingDetector.swift#L309-L392)).
  - Per-process holders (`kAudioProcessPropertyBundleID`) are read only to skip the case where **every** holder is a dictation app: `com.superduper.superwhisper`, `com.electron.wispr-flow`, `com.goodsnooze.macwhisper`, `com.prakashjoshipax.voiceink`, matched by prefix ([#L39-L65](https://github.com/yazinsai/OpenOats/blob/b27bf0156bf47cbca4d2adbee7a4a14fb7f0e410/OpenOats/Sources/OpenOats/Meeting/MeetingDetector.swift#L39-L65), [#L419-L435](https://github.com/yazinsai/OpenOats/blob/b27bf0156bf47cbca4d2adbee7a4a14fb7f0e410/OpenOats/Sources/OpenOats/Meeting/MeetingDetector.swift#L419-L435)).
  - Meeting apps: Zoom, Teams classic/new, FaceTime, Webex, Tuple, Around, Slack, Discord, WhatsApp, Meet PWA, OpenPhone ([#L465-L478](https://github.com/yazinsai/OpenOats/blob/b27bf0156bf47cbca4d2adbee7a4a14fb7f0e410/OpenOats/Sources/OpenOats/Meeting/MeetingDetector.swift#L465-L478)).
- **Asks by default.** Auto-record without a prompt is opt-in (`defaults.bool`, false when unset), needs prior consent, and still posts an "auto-recording started" notification. If that notification fails it falls back to the prompt ("silent capture is never acceptable") ([O App/MeetingDetectionController.swift#L405-L428](https://github.com/yazinsai/OpenOats/blob/b27bf0156bf47cbca4d2adbee7a4a14fb7f0e410/OpenOats/Sources/OpenOats/App/MeetingDetectionController.swift#L405-L428); [O Settings/SettingsStore.swift#L1592](https://github.com/yazinsai/OpenOats/blob/b27bf0156bf47cbca4d2adbee7a4a14fb7f0e410/OpenOats/Sources/OpenOats/Settings/SettingsStore.swift#L1592)).
- **Stop:** the mic is released and the camera is off, or **15 min (900 s) since the last utterance** ([O MeetingDetectionController.swift#L275-L300](https://github.com/yazinsai/OpenOats/blob/b27bf0156bf47cbca4d2adbee7a4a14fb7f0e410/OpenOats/Sources/OpenOats/App/MeetingDetectionController.swift#L275-L300), default at [SettingsStore.swift#L1602-L1610](https://github.com/yazinsai/OpenOats/blob/b27bf0156bf47cbca4d2adbee7a4a14fb7f0e410/OpenOats/Sources/OpenOats/Settings/SettingsStore.swift#L1602-L1610)).

### Meetily

- At `a2cb62e`, the Tauri backend has no code for process mic-in-use, device-running or power assertions. A grep for `IsRunningInput`, `DeviceIsRunningSomewhere`, `IOPMCopyAssertions` and `auto_detect` finds only summary-language code. Auto-detection is an open request ([meetily #218](https://github.com/Zackriya-Solutions/meetily/issues/218), opened 2025-10-25).

## 6. pasrom details not in the prior-art note

- **Mic-in-use list, allowlist only.**
  - The list is WeChat (`com.tencent.xinWeChat`; its sandboxed helpers deliberately not listed), Tencent Meeting (`com.tencent.meeting`, `com.tencent.tencentmeeting`, `com.tencent.wemeet`), FaceTime (`com.apple.FaceTime`, `com.apple.avconferenced`) and WhatsApp (`net.whatsapp.WhatsApp`) ([P MicInputDetector.swift#L51-L84](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/MicInputDetector.swift#L51-L84)).
  - User-added bundle IDs also match `<id>.*` helpers, because "Electron/Chromium apps capture the mic in a helper bundle such as `com.example.callapp.helper`" ([#L35-L42](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/MicInputDetector.swift#L35-L42), [#L89-L96](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/MicInputDetector.swift#L89-L96)).
  - Because nothing outside the allowlist ever starts, there is **no ignore list**. No `ignore`/`exclude` logic for mic holders exists in `Sources/`.
- **The browser channel's only exclusion** is `claimedProcesses`: every native pattern's process and owner names, taken from all known apps rather than only the watched ones. A native client is therefore never also a browser meeting, and turning an app off never hands it to the browser path ([P PowerAssertionDetector.swift#L416-L466](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/PowerAssertionDetector.swift#L416-L466)). Its comment says Teams "plausibly holds the identical WebRTC assertion". That was not measured.
- **Browser consent flow:**
  - The prompt reads "Record browser meeting? A meeting is active in <browser>" ([P WatchLoop+Consent.swift#L24-L56](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/WatchLoop+Consent.swift#L24-L56)).
  - The prompt times out after 60 s ([P ConsentPromptCoordinator.swift#L25](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/ConsentPromptCoordinator.swift#L25)).
  - A decline suppresses the question for 10 min, an expired prompt for 1 min, and "Never" adds the browser to a persistent deny list ([P BrowserConsentPolicy.swift#L38](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/BrowserConsentPolicy.swift#L38), [WatchLoop+Consent.swift#L84-L104](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/WatchLoop+Consent.swift#L84-L104)).
  - If the call has ended by the time the user approves, nothing starts ([#L113-L118](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/WatchLoop+Consent.swift#L113-L118)).
  - Asking does not block native detection (issue #543, [#L6-L16](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/WatchLoop+Consent.swift#L6-L16)).
- **4 h cap:**
  - On an auto recording, `waitForMeetingEnd` simply returns when the cap is hit, logging "Max recording duration reached" ([P WatchLoop.swift#L476-L505](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/WatchLoop.swift#L476-L505)).
  - `runMeeting` then calls `detector.reset`, which sets the 5 s cooldown, and goes back to polling ([#L383-L410](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/WatchLoop.swift#L383-L410)). If the call's assertion is still held, a **new** recording starts about 11 s later: 5 s cooldown + 2 × 3 s polls. The cap splits a long call; it does not end it **(inference, from the control flow)**.
  - No user-facing notice was found.
- **Manual start vs auto:**
  - A manual start (app tap or mic-only) **cancels the auto-watch loop** ([P WatchLoop.swift#L253-L271](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/WatchLoop.swift#L253-L271)).
  - A manual recording stops only when the target PID exits or at the 4 h cap. A mic-only recording has nothing that can exit, so the cap is its only stop. Power assertions are not consulted ([P ManualRecordingMonitorPolicy.swift#L53-L65](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/ManualRecordingMonitorPolicy.swift#L53-L65), [P WatchLoop+ManualRecording.swift#L14-L41](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/WatchLoop+ManualRecording.swift#L14-L41)).
  - Issue #549 (closed) added an auto/manual `trigger` field to the record-only sidecar, so downstream consumers can treat the two differently.

## Implications for Carbon (inference)

Carbon detects four signals:

- **M**, the mic: a non-ignored process holds input for ≥ 15 s.
- **E**, an EventKit event: one in its window, from 5 min before start to its end.
- **A**, a **native call assertion** on a known app's process: Zoom `zoom.us` with `PreventUserIdleDisplaySleep`/`NoDisplaySleepAssertion`, Teams `MSTeams`/`Microsoft Teams*` named "call in progress", or Webex named "On a call".
- **W**, Chromium's "WebRTC has active PeerConnections", under the main process name.

### (a) Which signals start a Meeting, which only offer

| Signals present | Action | Why |
|---|---|---|
| M + E | **Start** (current design) | Two independent signals, and the calendar names the Meeting |
| A + E | **Start** | Covers joining muted, or Teams helper-only mic bursts (LokalBot #179 in [native-meeting-app-audio-processes.md](native-meeting-app-audio-processes.md)). A is call-scoped by measurement for Zoom, Teams and Webex |
| M + A, same app, no event | **Start** | Ad hoc native call: two signals from the same app |
| M alone, no event | **Offer** | Hyprnote and OpenOats both ask on mic-only. pasrom refuses to auto-start Safari for this reason (#563) |
| A alone, no event | **Offer** | A vendor-controlled string with no second signal. Zoom #562 and Webex #652 show that the strings drift |
| W alone | **Nothing** (log only) | Fires on any ICE-checking PeerConnection, including an unjoinable Meet page and data channels (§2). Absent in Safari and Firefox |
| W + M, same browser, no event | **Offer**, naming the browser | W only sharpens the offer text. It never upgrades an offer to a start |
| E alone | **Nothing** | Hyprnote auto-starts on event + link, but Carbon has nothing to capture without a call app |

- Keep W optional. It adds little: M already covers every browser, Safari and Firefox included. Its only value is to word the offer ("call in Chrome" versus "Chrome is using the mic").
- **Do not ignore** `com.apple.WebKit.GPU`: it is Safari's mic owner. Attribute it to Safari through its responsible process, or show it as "Safari" when naming the offer. Measuring this is part of the hand-run checks below.
- **Stop:** where A was present at start, treat "A released ≥ 15 s **and** M released" as the call end. Then stop after the 30 s silence **without** waiting for the event to end. A user who leaves early is then not recorded until the event ends. Without A, keep the current rule.

### (b) Initial thresholds

| Parameter | Value | Basis |
|---|---|---|
| Confirm delay (M) | **15 s** | Carbon's design; Hyprnote ships 15 s; pasrom (6 s) is the lower bound |
| Assertion poll / confirm (A, W) | **every 3 s, 2 consecutive hits**, polled only while M is held or an event is in its window | pasrom; 0.11 ms per call, so cost is not a constraint; the private push channel is not worth it (§1) |
| Stop grace after M (and A) released | **15 s**, then the existing **30 s silence** + event ended; with A released, skip "event ended" | pasrom 15 s grace; Hyprnote 5 s + AX veto |
| No-event stop | **10 min silence** after release (keep) | Between Minute (2.5 min) and OpenOats (15 min) |
| Back-to-back split | Split when **any** of these holds: (1) the matched event ends and another event starts while M is still held. Hyprnote's rule is the model: a hold that began ≥ 10 min before the new start, during another event, belongs to that earlier call. (2) The native assertion's `AssertionId`/`GlobalUniqueID` changes, or its `AssertStartWhen` moves later, while M stays held. (3) M and A are both released ≥ **5 s** (pasrom cooldown). | Rule (2) is untested: it assumes Zoom and Teams create a new assertion per call. pasrom #765 shows that a release gap alone merges Teams calls |
| Cap | **4 h**; at the cap, end the Meeting and re-run the start rules, so a still-live call becomes a new Meeting | pasrom's behaviour (§6) |
| Offer prompt | **60 s** timeout; decline → **10 min** per-app quiet; expired → 1 min; "Never" → add to the ignored list | pasrom consent policy; Hyprnote 10 min per-app cooldown |

### (c) Initial ignored-process list (bundle IDs)

- **Settled:**
  - Carbon's own bundle ID;
  - `com.apple.CoreSpeech`.
- **From Hyprnote's default list:**
  - Dictation and voice memos:
    - `com.electron.wispr-flow`
    - `com.superduper.superwhisper`
    - `com.goodsnooze.macwhisper`
    - `com.prakashjoshipax.VoiceInk`
    - `com.seewillow.WillowMac`
    - `com.electron.aqua-voice`
    - `com.descript.beachcube`
    - `com.apple.VoiceMemos`
  - Screen recorders:
    - `com.apple.QuickTimePlayerX`
    - `com.apple.screenshot.launcher`
    - `com.loom.desktop`
    - `com.obsproject.obs-studio`
    - `pl.maketheweb.cleanshotx`
    - `com.getcleanshot.app-setapp`
    - `com.timpler.screenstudio`
    - `so.cap.desktop`
    - `com.wulkano.kap`
    - `com.wulkano.kap.helper`
    - `net.telestream.screenflow10`
    - `com.techsmith.camtasia`
    - `com.techsmith.camtasia2024`
    - `com.TechSmith.Snagit`
    - `com.TechSmith.Snagit2024`
  - AI assistants with voice:
    - `com.openai.chat`
    - `com.openai.codex`
    - `com.anthropic.claudefordesktop`
  - Other:
    - `com.raycast.macos`
    - `com.apple.garageband10`
    - `com.apple.Sound-Settings.extension`
- **Optional, from Hyprnote's IDE category:** `com.microsoft.VSCode`, `com.todesktop.230313mzl4w4u92` (Cursor), `com.exafunction.windsurf`, `dev.warp.Warp-Stable`. They hold the mic for voice input. The cost of listing them is missing a Live Share call.
- **Never ignore:**
  - `com.apple.avconferenced` (FaceTime);
  - `com.apple.WebKit.GPU` (Safari calls);
  - browser and Electron helpers (resolve them to the outermost `.app`, as Hyprnote does);
  - `com.apple.TelephonyUtilities.callservicesd` (iPhone calls relayed to the Mac). Treat these as M-only, i.e. offer.
- Add pasrom's "log each unmatched mic holder once" diagnostic. It catches Siri and other Apple daemons that no source lists. **Siri's own bundle IDs are not covered by any source read here.**

### Uncertain, needs a hand-run check (`pmset -g assertions` plus Core Audio snapshots)

1. Does Zoom keep or re-create its assertion between back-to-back calls? Does `AssertionId` change?
2. Do Teams back-to-back calls re-create "call in progress"?
3. Does a Slack huddle hold "WebRTC has active PeerConnections" under "Slack"? Does Discord voice hold any assertion?
4. Is Safari's mic holder `com.apple.WebKit.GPU` on macOS 26, and which call resolves it to Safari?
5. Which processes hold the mic for Siri and system dictation besides `com.apple.CoreSpeech`?
6. Does Zoom keep the mic while muted?
