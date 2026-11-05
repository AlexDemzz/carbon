# Zoom and Meet across back-to-back calls

Researched 2026-11-05. Carbon's Detector is losing its "Event ended and another began while the mic stayed held → split" rule, because that rule cut a Google Meet call that ran over. This note asks whether the remaining rules still separate two back-to-back calls:

- **R1:** the Meeting App's call power assertion has only new `AssertionId`s (none of the old ones left) while the mic stays held;
- **R2:** the Meeting App's mic and call assertion are both released for ≥ 5 s (`backToBackGap`), then a start signal comes back;
- **R3 (browsers):** "WebRTC has active PeerConnections" and the mic are both released for ≥ 10 s (`webRTCReleaseGrace`).

Nobody on the team has Zoom, so nothing here was measured by Carbon. It builds on four notes and does not repeat them: [power-assertions-detection.md](power-assertions-detection.md) (IOPM API, Chromium's wake lock, Zoom's "Describe Activity Type"), [native-meeting-app-audio-processes.md](native-meeting-app-audio-processes.md) (Zoom's helper processes, Granola's "may keep the microphone active"), [meeting-end-detection-competitors.md](meeting-end-detection-competitors.md) (end signals, Meet room-code splits) and [prior-art-minute-meeting-transcriber.md](prior-art-minute-meeting-transcriber.md) (pasrom's 5 s cooldown).

Labels: **verified** = read in source code or vendor docs, or measured by a named project; **reported** = a vendor or secondary claim with no published measurement; **inferred** = my conclusion; **no source found** = I looked and found nothing.

## Sources and pins

| Source | Pin | What it is |
|---|---|---|
| [apple-oss-distributions/PowerManagement](https://github.com/apple-oss-distributions/PowerManagement/tree/d415e45501842834a280930c3eed9186544a67f0) | `d415e45` (same as the power-assertions note) | `powerd`: how `AssertionId`s are allocated |
| [apple-oss-distributions/IOKitUser](https://github.com/apple-oss-distributions/IOKitUser/tree/323ead896d04424f87184d8f6ff0cce811aab106) | `323ead8` | Client side, async assertions |
| macOS SDK `CoreAudio/AudioHardware.h`, `AVFAudio/AVAudioApplication.h` | Xcode 26.4 SDK | `IsRunningInput` and per-app input mute definitions |
| [chromium/chromium](https://github.com/chromium/chromium/tree/2fc1d860a6db11710202e674c0446c2e5296c6c9) | `2fc1d86` (same as the power-assertions note) | `webrtc_internals.cc`, `wake_lock.cc` |
| [pasrom/meeting-transcriber](https://github.com/pasrom/meeting-transcriber) | PR #475 `b2867e5`, PR #820 `232f992`, issues #510, #765 | Measured Zoom idle/in-call assertions and Teams back-to-back IDs |
| [screenpipe/screenpipe](https://github.com/screenpipe/screenpipe/tree/b24121147cdd4ba03895a0c648cd828b4f673679) | `b241211` | Back-to-back boundary code |
| [stevyhacker/LokalBot](https://github.com/stevyhacker/LokalBot/tree/83784154af7095626a9f20920fa608ef41a8114d) | `8378415` | Calendar-handoff split, muted-Zoom comment |
| [Yang et al., "Are You Really Muted?", PoPETs 2022(3)](https://petsymposium.org/popets/2022/popets-2022-0077.pdf) | read 2026-11-05 | Traced mic access of muted VCAs on macOS with Instruments |
| Zoom, Google, Granola docs; press coverage of Zoom 5.9.3 | read 2026-11-05 | Linked inline |

## Summary

| Question | Answer | Confidence |
|---|---|---|
| 1. Does Zoom keep the mic between call 1 and call 2? | No source measures it. Zoom called a mic that stayed on after a meeting a bug and said 5.9.3 (Jan 2022) fixed it. Granola still warns that Zoom "may keep the microphone active between calls". No Zoom setting is documented to keep the mic open between meetings. | **reported** (release) / **no source** (gap length) |
| 2. Is the call assertion dropped and re-created, with a new `AssertionId`? | Zoom holds no display-sleep assertion while idle and one while in a call (pasrom, measured). A re-created assertion always gets a new `AssertionId` (powerd source). That Zoom releases it between two calls without quitting is not measured. Screen sharing: no source. Teams, measured: 3–9 s gap, new IDs. | **verified** (idle/in-call, ID allocation) / **inferred** (between calls) |
| 3. Does Zoom keep the mic open while muted? | Yes. On macOS, muted native apps, Zoom included, keep the mic indicator lit and keep reading the input's status flags. | **verified** (2022 paper; Zoom build of that time) |
| 4. Chrome + Meet, back-to-back | Second tab joined before leaving the first: the WebRTC lock is **continuous** (one browser-wide counter). The mic is continuous too (inferred). Same tab: the mic is released on leave and re-opened by the next green room. The gap is whatever the person takes to open the next link. No source measures it, and screenpipe says it is "well inside" 20 s. | **verified** (lock) / **inferred** (mic) / **reported** (gap) |

## 1. Zoom's mic between two calls

- **Zoom treats a mic held after a meeting as a bug.** Zoom 5.9.1 (2021-12-27) release notes listed "resolved an issue regarding the microphone light indicator being triggered when not in a meeting on macOS Monterey". A Zoom spokesperson later said 5.9.3 (2022-01-25) "fixed a bug involving the failure to properly terminate the microphone use post-meeting" ([Macworld](https://www.macworld.com/article/613921/zoom-mac-bug-microphone.html), [9to5Mac](https://9to5mac.com/2022/02/11/zoom-update-prevents-microphone-from-staying-active-after-calls-on-mac/)). **Reported:** this is press quoting Zoom; I could not find the 5.9.1 entry on Zoom's current [release-notes page](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0061222). Users still reported the indicator after 5.9.3 (same articles).
- **Granola** (vendor doc, no measurement): "If you jump directly from one call to another, your meeting app (e.g. Zoom) may keep the microphone active between calls … Granola can't detect that the first meeting ended" ([Granola](https://docs.granola.ai/help-center/taking-notes/transcription)). Already in the native-apps note. **Reported.** It may describe the 2021 bug, Granola's device-level signal, or a person who joins call 2 within seconds. The doc doesn't say which.
- **Detectors that assume Zoom releases it:**
  - shogo-ai treats `IsRunningInput` as the only sign that a Zoom call is live ([meeting-detector.ts L155-L162](https://github.com/shogo-labs/shogo-ai/blob/afb1bf6d29df14eacfc5d1cc7542409829e694fe/apps/desktop/src/detection/meeting-detector.ts#L155-L162)).
  - screenpipe's native back-to-back rule is "a native app (no URL) drops the mic and re-takes it after the bound calendar event ended" ([room_change.rs L27-L29](https://github.com/screenpipe/screenpipe/blob/b24121147cdd4ba03895a0c648cd828b4f673679/crates/screenpipe-engine/src/meeting_watcher/audio_process/room_change.rs#L27-L29)).
  - Neither project publishes a measurement of the gap. **Inferred:** they expect a release.
- **Settings that change when the mic opens.** No source ties any of these to `IsRunningInput`:
  - "Automatically join audio by computer when joining a meeting": when it is off, a join-audio prompt appears first ([Boise State IT](https://boisestate.atlassian.net/wiki/spaces/LTS/pages/42008654/Audio+Settings), [Creighton](https://myservices.creighton.edu/TDClient/32/Portal/KB/Article/441/Testing-and-Joining-My-Computer-Device-Audio-in-Zoom); secondary). **Inferred:** the mic opens on "Join with Computer Audio", or on "Test speaker and microphone" in that prompt, which moves the mic's first use later in call 2.
  - The pre-join preview "displays the selected audio and video sources" ([devicebase summary of Zoom release notes](https://devicebase.net/en/zoom-zoom-video-conferencing/updates/release-notes-for-the-zoom-workplace-app/6if); secondary). Whether it opens the mic: **no source found**.
  - Waiting room: participants "cannot see or hear anyone" until admitted ([Zoom Community](https://community.zoom.com/meetings-2/waiting-room-questions-79808), secondary). Whether the mic or the assertion is held there: **no source found**.
  - "Join different meetings simultaneously on desktop" is an account setting, off by default. With it on, one client can be in two meetings at once ([Stony Brook IT](https://it.stonybrook.edu/help/kb/join-multiple-zoom-meetings-simultaneously-on-desktop), [U-M](https://teamdynamix.umich.edu/TDClient/76/Portal/KB/Article/5080/Can-I-join-multiple-Zoom-meetings-at-the-same-time); secondary). Then the mic can stay held across two calls **(inferred)**.
  - Original sound: **no source found**.
- **Who holds it.** Carbon attributes helpers to `us.zoom.xos` through the responsible process, so "Zoom holds the mic" covers `us.zoom.xos` and `us.zoom.caphost`, the two processes measured holding input (native-apps note).

## 2. Zoom's call assertion

- **Not held while idle, held in a call (verified, measured):** "in-call, `zoom.us` holds a `NoDisplaySleepAssertion`; idle (Zoom open, no meeting) it holds no display-sleep assertion at all". The `caphost` helper "holds no assertion during a call" ([pasrom PR #475](https://github.com/pasrom/meeting-transcriber/pull/475), merged as `b2867e5`). "Idle" means the Zoom home window.
- **Created when the call starts (verified, one sample):** a solo test meeting showed `pid 88352(zoom.us): [0x002c22020005934d] 00:00:03 NoDisplaySleepAssertion named: "Describe Activity Type"`. The assertion was 3 s old, on Zoom 7.0.5 ([pasrom #510](https://github.com/pasrom/meeting-transcriber/issues/510)).
- **The name comes from a create-then-release sample.** Apple's QA1340 Listing 2 is `CFSTR("Describe Activity Type")` → `IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep, …)` → work → `IOPMAssertionRelease` ([Apple QA1340](https://developer.apple.com/library/archive/qa/qa1340/_index.html)). **Inferred:** Zoom wraps the in-meeting period in that pattern and releases the assertion when the meeting window closes. Nobody has logged it between two calls without quitting.
- **A re-created assertion always has a new `AssertionId` (verified, source):**
  - `powerd` allocates IDs round-robin over 10 240 slots shared by every process: `ID_FROM_INDEX(idx) = (idx & 0x7fff) | 0x8000`, and `gNextAssertionIdx` moves past each new ID ([PM PMAssertions.h#L107-L125](https://github.com/apple-oss-distributions/PowerManagement/blob/d415e45501842834a280930c3eed9186544a67f0/pmconfigd/PMAssertions.h#L107-L125), [PMAssertions.c#L5974-L6008](https://github.com/apple-oss-distributions/PowerManagement/blob/d415e45501842834a280930c3eed9186544a67f0/pmconfigd/PMAssertions.c#L5974-L6008)). Reuse needs a full wrap of 10 240 creations in between.
  - The `[0x…]` in `pmset` is `GlobalUniqueID` = creation time << 32 | type << 16 | `AssertionId` (`MAKE_UNIQAID`, same header). In #510's `0x…934d`, `AssertionId` is `0x934d`.
  - Client-side async IDs apply only to system-sleep types ([IK IOPMAssertions.c#L814-L831](https://github.com/apple-oss-distributions/IOKitUser/blob/323ead896d04424f87184d8f6ff0cce811aab106/pwr_mgt.subproj/IOPMAssertions.c#L814-L831)), so they never apply to Zoom's display-sleep assertion.
  - A level toggle (`IOPMAssertionSetLevel`) keeps the ID. **Inferred:** if Zoom ever turned its assertion off and on instead of releasing it, R1 would never see a new ID.
- **Teams, the only measured analog (verified):** per call, `MSTeams` holds two "Call in progress" assertions. "Between two calls Teams releases them. The gap was **3–9 s** … Each new call gets **new assertion IDs**. Within a call the IDs stay stable", including across a ~6.5 s Wi-Fi drop ([pasrom PR #820](https://github.com/pasrom/meeting-transcriber/pull/820), fix for [#765](https://github.com/pasrom/meeting-transcriber/issues/765)).
- **pasrom chose not to split Zoom on IDs.** It made ID-based splitting "on for Teams only, the one app that was measured. Zoom also matches by assertion type, and an unrelated display-sleep assertion recreated mid-call would split a call" (PR #820). It also lists as unmeasured "long network outage, lobby admission, hold/resume" and "joining the next meeting directly from a running one: if both assertion pairs coexist briefly … the split does not fire".
- **Outside a call:**
  - Home window: none (PR #475, above).
  - Screen sharing inside a call, Zoom Clips, webinars, breakout rooms: **no source found**.
  - A dotfiles commit says Zoom "keeps [the display] lit with a 'Describe Activity Type' assertion" and releases it "when the call … ends" ([asktt1770/dotfiles b9c008f](https://github.com/asktt1770/dotfiles/commit/b9c008f81ebf8ae4e3f7961e0b61a301d23c4a97)). **Reported**, no data.

## 3. Zoom's mic while muted

- **Verified (measured on macOS, 2021-era builds):**
  - Yang et al. traced the VCAs with Instruments and tcpdump. For most native apps, Zoom included, "the microphone status indicator in Windows and macOS remains continuously illuminated". They "check if a user is talking even while muted but do not continuously sample audio in the same way" (§4.3, pp. 381–382).
  - "Zoom alerts the user when they try to speak with their microphone muted" (§6.3).
  - Webex alone reads raw audio while muted ([PoPETs 2022-0077](https://petsymposium.org/popets/2022/popets-2022-0077.pdf)).
  - **Inferred:** a lit indicator means the input IO runs, so `IsRunningInput` = 1. The header defines that as "running IO and there is at least one active input stream" (`AudioHardware.h` L1967-L1970).
- **Still current (reported):** Zoom shows a "speaking while muted" reminder, which needs the input running ([devicebase summary](https://devicebase.net/en/zoom-zoom-video-conferencing/updates/release-notes-for-the-zoom-workplace-app/6if); a [Zoom Community reply](https://community.zoom.com/t5/Zoom-Meetings/In-meeting-notification/m-p/144000) says it fires on "audio activity above a certain threshold … while you're muted").
- **Apple's per-app mute also keeps IO running.** `AVAudioApplication.setInputMuted` makes input samples "zeroed out" and "doesn't affect the hardware mute state" (`AVAudioApplication.h` L81-L84, macOS 14+). **Inferred:** an app that mutes this way still shows `IsRunningInput` = 1.
- **One conflicting claim, unsourced.** LokalBot says the mic signal "misses … Zoom call with mic muted", in a comment borrowed from another project with no measurement ([AudioSourceMonitor.swift L5-L10](https://github.com/stevyhacker/LokalBot/blob/83784154af7095626a9f20920fa608ef41a8114d/LokalBot/Services/AudioSourceMonitor.swift#L5-L10)). It may mean joining muted, where Zoom might not open the mic until the first unmute. **No source found** either way.

## 4. Chrome + Google Meet

- **The WebRTC lock is one counter for the whole browser (verified, source):**
  - `num_connected_connections_` counts every PeerConnection in `checking`/`connected`/`completed` across all tabs. `UpdateWakeLock()` cancels the lock only at 0 ([CR webrtc_internals.cc#L881-L925](https://github.com/chromium/chromium/blob/2fc1d860a6db11710202e674c0446c2e5296c6c9/content/browser/webrtc/webrtc_internals.cc#L881-L925)).
  - A closed tab or renderer removes its connections ([#L235-L251](https://github.com/chromium/chromium/blob/2fc1d860a6db11710202e674c0446c2e5296c6c9/content/browser/webrtc/webrtc_internals.cc#L235-L251), [#L805-L828](https://github.com/chromium/chromium/blob/2fc1d860a6db11710202e674c0446c2e5296c6c9/content/browser/webrtc/webrtc_internals.cc#L805-L828)).
  - The device service builds a new `PowerSaveBlocker`, and so a new IOPM assertion, only when its request count goes from 0 to 1 ([CR services/device/wake_lock/wake_lock.cc#L62-L92](https://github.com/chromium/chromium/blob/2fc1d860a6db11710202e674c0446c2e5296c6c9/services/device/wake_lock/wake_lock.cc#L62-L92), [#L128-L157](https://github.com/chromium/chromium/blob/2fc1d860a6db11710202e674c0446c2e5296c6c9/services/device/wake_lock/wake_lock.cc#L128-L157)).
  - So if Meet B connects in a new tab before Meet A is left, the assertion never drops and keeps its ID.
- **The mic with two tabs (inferred):**
  - `IsRunningInput` is 1 while the process has "at least one active input stream" (`AudioHardware.h` L1967-L1970).
  - Carbon folds every Chrome helper into `com.google.Chrome` through the responsible process (`App/Sources/Adapters/AudioProcesses.swift` L56-L72).
  - Two overlapping tab captures therefore give a continuous hold. I did not read how Chromium shares input streams across tabs, and it does not matter for this result.
- **The green room opens the mic (verified, vendor):** before joining, "click Microphone and speak. If the mic bar moves, your mic works" ([Google Meet Help: Before a meeting](https://support.google.com/meet/answer/10409699)). pasrom adds that Meet "raises the same WebRTC assertion on a page you cannot even join" ([P WatchLoop+Consent.swift#L10-L16](https://github.com/pasrom/meeting-transcriber/blob/1765408a99b4c1360735648df7f41055e647f4a5/app/MeetingTranscriber/Sources/WatchLoop+Consent.swift#L10-L16)).
- **Same tab, leave A then join B:**
  - The mic is released on leave and re-taken as soon as B's green room loads. The gap is the person's navigation time.
  - screenpipe (code comment, no data): "leaving Meet room A and joining room B in the same browser reuses the same process, often the same audio session, and happens well inside the 20s grace" ([room_change.rs L8-L17](https://github.com/screenpipe/screenpipe/blob/b24121147cdd4ba03895a0c648cd828b4f673679/crates/screenpipe-engine/src/meeting_watcher/audio_process/room_change.rs#L8-L17)). That is why screenpipe and Omi split on a Meet room-code change instead (end-detection note).
  - Measured gap: **no source found**.
- **LokalBot** keeps the calendar split for this case: "A live recording backed by one calendar event should split immediately when the active calendar event changes. This prevents back-to-back meetings from being merged during the stop debounce" ([MeetingMatcher.swift L196-L202](https://github.com/stevyhacker/LokalBot/blob/83784154af7095626a9f20920fa608ef41a8114d/LokalBot/Services/Calendar/MeetingMatcher.swift#L196-L202)). It splits browsers only when the next event uses the **same** room link, and treats a different room as "running over" ([MeetingDetector.swift L861-L864](https://github.com/stevyhacker/LokalBot/blob/83784154af7095626a9f20920fa608ef41a8114d/LokalBot/Services/MeetingDetector.swift#L861-L864)).

## What this means for Carbon (opinion)

- **R1 is sound for Zoom, but only in theory.** powerd guarantees a new ID for a new assertion, and Zoom holds none while idle. If Zoom releases the assertion between calls, as Teams does, R1 splits even when the gap is under 5 s. Until someone measures it, treat R1 for Zoom as unproven, as pasrom does.
- **Carbon matches Zoom by type only** (`VendorTable.json`: `us.zoom.xos` + `PreventUserIdleDisplaySleep`). Any Zoom display-sleep assertion re-created during a call, with the mic held, ends that call as `.backToBack`. That covers a reconnect, waiting-room admission, a breakout-room move, or a share that swaps assertions. This is the exact risk pasrom named for Zoom. Measure these cases before relying on R1, or require a short gap where neither the old IDs nor the mic were held.
- **R1 misses overlapping assertions.** `endReason` replaces `callIDs` with the current set on every poll (`Detector.swift` L227). If call 2's assertion appears before call 1's is released, as with simultaneous meetings or a join straight from a running call, the next poll sees `{new}` ⊂ `{old, new}`, never a disjoint set, and the calls merge. Keeping the IDs from the Meeting's first confirmed poll, and splitting once none of those are left, would fix it. pasrom flags the same case.
- **R2 depends on human speed.** A person who leaves Zoom and clicks the next join link within 5 s, with the new assertion not yet up, gets no R2 split. R1 then has to catch it.
- **Browsers lose their back-to-back split.**
  - Joining Meet B in a new tab before leaving A gives no signal at all. That is Chromium by design (§4).
  - A same-tab switch splits only if both signals stay down for ≥ 10 s. The green room makes that unlikely.
  - Removing the Event rule therefore merges most back-to-back Meets, as Granola admits for itself. The only signal that separates them is the Meet room code, from the URL or the window title (screenpipe, Omi). That is a later option, not a reason to keep a rule that cuts overrunning calls.
- **Muting is harmless.** Zoom keeps the mic open while muted, so a muted stretch never looks like a release. That rests on 2022 data; re-check it in the measurement below.

## Open questions and a manual measurement plan

Open:
1. Does Zoom release "Describe Activity Type" between calls without quitting, and how long is the gap?
2. Is the assertion re-created inside one call: reconnect, waiting room → admitted, breakout rooms, screen share start/stop, host transfer?
3. Is the assertion or the mic held in the waiting room, the pre-join preview, or the join-audio "Test speaker and microphone" step?
4. Joined muted, with "Mute my microphone when joining": does Zoom open the mic before the first unmute? (LokalBot's claim.)
5. Meet: after Leave, while the "You left the meeting" page is open, is the WebRTC lock still held? How many seconds pass between leaving A and B's green room taking the mic in the same tab?

**Probe.** Save as `probe.swift` and build with `swiftc -O probe.swift -o probe`. Tested on macOS 27.0.1. It prints every process with `IsRunningInput` = 1, plus the default input's `DeviceIsRunningSomewhere`:

```swift
import CoreAudio
import Foundation

func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
}

func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
    var addr = address(selector), value: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
    AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value)
    return value
}

func processes() -> [AudioObjectID] {
    var addr = address(kAudioHardwarePropertyProcessObjectList), size: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
    var list = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &list)
    return list
}

func bundleID(_ process: AudioObjectID) -> String {
    var addr = address(kAudioProcessPropertyBundleID), ref: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    AudioObjectGetPropertyData(process, &addr, 0, nil, &size, &ref)
    return ref?.takeRetainedValue() as String? ?? "?"
}

let stamp = ISO8601DateFormatter().string(from: Date())
let input = uint32(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice)
print(stamp, "default-input-running-somewhere=\(uint32(input, kAudioDevicePropertyDeviceIsRunningSomewhere))")
for process in processes() where uint32(process, kAudioProcessPropertyIsRunningInput) == 1 {
    print(stamp, "input pid=\(uint32(process, kAudioProcessPropertyPID))", bundleID(process))
}
```

**Logger.** Run one sample per second for the whole session. The last four hex digits of `[0x…]` are the `AssertionId`:

```sh
while true; do
  ./probe
  pmset -g assertions | grep -E '\((zoom\.us|caphost|CptHost|Google Chrome)\)|PeerConnections' | sed "s/^/$(date -u +%FT%TZ) /"
  sleep 1
done | tee zoom-b2b.log
```

**Zoom run.** Note the Zoom version and the Audio settings first: auto-join computer audio, mute on join, and video preview.

1. Zoom open on the home window, 30 s: the baseline.
2. Join call 1. Note when the preview, waiting room, join-audio prompt and admission happen.
3. In call 1: mute 30 s, unmute, share the screen 30 s, stop, then Wi-Fi off for 10 s and back on.
4. Leave. Stay on the home window 10 s, then join call 2 by link. Leave.
5. Repeat step 4, but click call 2's link within 2 s of leaving.
6. If the account allows "Join different meetings simultaneously", join call 2 while still in call 1.
7. Optional: join with "Mute my microphone when joining" on, and enter and leave a breakout room.

**Meet run (Chrome).**

1. Join A. Open B in a new tab, join it, then leave A.
2. Same tab: leave B, stay 10 s on "You left the meeting", paste C's link, and join from the green room.

**Read the log for:** the seconds with no `us.zoom.*` or Chrome input; each `AssertionId`'s first and last time; whether two IDs ever coexist; and any ID change inside one call.
