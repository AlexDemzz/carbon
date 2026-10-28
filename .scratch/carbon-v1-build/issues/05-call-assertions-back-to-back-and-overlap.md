# 05: Call assertions, back-to-back splitting, the 4 h cap and overlapping Meetings

**What to build:** native Zoom, Teams and Webex calls start even when the person joins muted, and end soon after hang-up. Back-to-back calls become separate Meetings. A forgotten call is cut at 4 h, then restarts as a new Meeting if it is still live. A second call app taking the mic during a live Meeting never mixes into it: a notification offers "Switch to <app>" instead. Spec: Detector (call assertion rules, back-to-back, the cap, overlapping Meetings), SignalSampler (IOPM polling), Vendor table.

**Blocked by:** 03 (Auto-start and auto-stop on microphone Detection).

**Status:** ready-for-agent

- [ ] `IOPMCopyAssertionsByProcess()` is polled every 3 s while the mic is held or an Event is in its window.
- [ ] The vendor table matches Zoom, Teams "call in progress" and Webex "On a call", in both modern and legacy type spellings.
- [ ] A call assertion confirmed on 2 consecutive polls starts a Meeting on its own.
- [ ] Browser WebRTC assertions are logged only.
- [ ] A Meeting with a call assertion ends once the assertion and the mic have been released for 15 s, followed by 30 s of silence.
- [ ] Back-to-back: a new Meeting starts on an `AssertionId` change while the mic stays held, or after the mic and the assertion have both been released for 5 s or more, with a 5 s cooldown. The Event-based trigger comes with ticket 06.
- [ ] At the 4 h cap the Meeting ends and the start rules run again.
- [ ] Overlap: at most one live Meeting. A start signal from another app posts "<app> is using the microphone." / "Carbon is still transcribing "<title>"." with "Switch to <app>". Switching ends the current Meeting and starts the other app's at once.
- [ ] The Detector test table covers every rule above.
