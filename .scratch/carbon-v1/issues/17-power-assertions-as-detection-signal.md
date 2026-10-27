# Power assertions as a Detection signal

Type: research
Status: resolved
Blocked by:
Assignee: alexandre

## Question

Should Detection use macOS power assertions (Zoom/Teams/Webex call assertions, Teams' "call in progress" only, browsers' "WebRTC has active PeerConnections") as a signal alongside mic-in-use and the calendar, as pasrom/meeting-transcriber ships (see "Prior art in Minute and meeting-transcriber")? Which signal starts a Meeting on its own, which only offers to, and does a browser WebRTC signal auto-start or ask, given "auto-transcribe by default" in "Carbon v1 product design"? Also fix the initial thresholds and ignored-process list from prior art (pasrom: ~6 s confirm, 15 s stop, 5 s back-to-back gap, 4 h cap; Minute: 120 s silence + 30 s countdown), since "Detection and auto-stop rules on real usage" is out of scope and tuning comes from dogfooding.

## Assets

- [Power assertions as a Detection signal](../../../docs/research/power-assertions-detection.md): Apple IOPM API (public header, no entitlement, ≈ 0.11 ms per call, no public push), Chromium/WebKit/Firefox source, known native-app assertions, Hyprnote and OpenOats rules, at pinned commits.

## Answer

**Yes: Detection reads power assertions, but only the native call assertions start anything.** `IOPMCopyAssertionsByProcess()` is public, needs no entitlement and costs ≈ 0.11 ms, so Carbon polls it every 3 s while the mic is held or a calendar event is in its window.

Signals:
- **Mic**: a non-ignored process holds input ≥ 15 s (unchanged).
- **Event**: an EventKit event from 5 min before its start to its end (unchanged).
- **Call assertion** (new), confirmed on 2 consecutive polls: Zoom (`zoom.us`, type `PreventUserIdleDisplaySleep` or `NoDisplaySleepAssertion`); Teams (`MSTeams` / `Microsoft Teams*`, name "call in progress" only, never the idle "Video Wake Lock"); Webex (name "On a call"). Type names are matched in both modern and legacy spellings. The strings are vendor-controlled and have drifted (pasrom #562, #652), so they live in one table that a Sparkle update can change.
- **Browser WebRTC assertion** ("WebRTC has active PeerConnections"): **not a signal.** It fires for any ICE-active PeerConnection, data channels and unjoined Meet pages included, and Safari and Firefox have no equivalent. The mic already covers every browser. It is logged for diagnostics only.

**Start rules.** With auto-transcribe on (the default), **Mic alone** or a **Call assertion alone** starts a Meeting. The Event names it when one is in its window; otherwise it gets the default title. With auto-transcribe off, the same rules show the "Transcribe?" banner instead. Neither the Event nor the browser assertion ever starts a Meeting.
- *Deviation from the research note:* the note proposed that Mic alone with no Event should only offer, as Hyprnote and OpenOats do. That would change the validated product ("Auto-transcribe on by default", "Meetings without a calendar event are transcribed with a default title" in "Carbon v1 product design"). So auto-start stays; the ignored-apps list is what keeps false starts down. Dogfooding reports of false starts are the trigger to revisit.
- The Call assertion alone starts a Meeting so that joining muted, or Teams helper-only mic bursts, are still caught. Its PID resolves to the Meeting App through the responsible PID, as for the mic.

**Stop rules.**
- Meeting started with or joined by a Call assertion: the Meeting ends when the assertion **and** the mic have been released for 15 s, then 30 s of silence. It does **not** wait for the Event to end, so leaving early doesn't keep recording.
- Otherwise, unchanged: mic released + 30 s silence + Event ended; no Event → mic released + 10 min silence.
- Cap: **4 h**. At the cap the Meeting ends and the start rules are re-run, so a call still live becomes a new Meeting.
- Manual Stop always wins. A manual start follows the same stop rules.

**Back-to-back.** A new Meeting starts, with a **5 s** cooldown after the previous one ends, when:
1. the matched Event ends and another Event starts while the mic is still held. This is Hyprnote's rule: a hold that began ≥ 10 min before the new Event belongs to the earlier call; or
2. the Call assertion's `AssertionId` changes while the mic stays held. This is unmeasured: it assumes Zoom and Teams create one assertion per call. pasrom #765 shows a release gap alone merges Teams calls; or
3. the mic and Call assertion were both released ≥ 5 s.

**Offer banner** (auto-transcribe off): 60 s timeout; a decline mutes that app for 10 min; "Never" adds it to the ignored apps.

**Ignored apps (initial list, by bundle ID; helpers resolved to their outermost `.app`):**
- Settled: Carbon, `com.apple.CoreSpeech`.
- Dictation and voice notes: `com.electron.wispr-flow`, `com.superduper.superwhisper`, `com.goodsnooze.macwhisper`, `com.prakashjoshipax.VoiceInk`, `com.seewillow.WillowMac`, `com.electron.aqua-voice`, `com.descript.beachcube`, `com.apple.VoiceMemos`.
- Screen recorders: `com.apple.QuickTimePlayerX`, `com.apple.screenshot.launcher`, `com.loom.desktop`, `com.obsproject.obs-studio`, `pl.maketheweb.cleanshotx`, `com.getcleanshot.app-setapp`, `com.timpler.screenstudio`, `so.cap.desktop`, `com.wulkano.kap`, `com.wulkano.kap.helper`, `net.telestream.screenflow10`, `com.techsmith.camtasia`, `com.techsmith.camtasia2024`, `com.TechSmith.Snagit`, `com.TechSmith.Snagit2024`.
- Voice assistants and tools: `com.openai.chat`, `com.openai.codex`, `com.anthropic.claudefordesktop`, `com.raycast.macos`, `com.apple.garageband10`, `com.apple.Sound-Settings.extension`.
- Editors with voice input. Included because Mic alone auto-starts; a Live Share call is the accepted miss: `com.microsoft.VSCode`, `com.todesktop.230313mzl4w4u92` (Cursor), `com.exafunction.windsurf`, `dev.warp.Warp-Stable`.
- **Never ignored:** `com.apple.avconferenced` (FaceTime), `com.apple.WebKit.GPU` (Safari calls, shown as Safari), `com.apple.TelephonyUtilities.callservicesd` (iPhone calls on the Mac), browser and Electron helpers.
- The person can add apps in Settings (and through "Never"). Carbon logs each unmatched mic holder once (pasrom's diagnostic), which surfaces Siri and other Apple daemons no source lists.

**Left to dogfooding, not hand-run:** Zoom and Teams assertions between back-to-back calls (`AssertionId` change), Slack huddle / Discord, Safari's mic holder on macOS 26, Siri and system-dictation processes, Zoom's mic while muted. The diagnostic log (unmatched mic holders, call and WebRTC assertions seen) is what the author sends back.
