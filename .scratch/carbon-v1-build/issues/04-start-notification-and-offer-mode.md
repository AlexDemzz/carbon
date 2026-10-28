# 04: Start notification, offer mode and the Settings window

**What to build:** the person always knows when Carbon is transcribing, and can refuse it. When a Meeting starts automatically, Carbon posts "Transcribing in <language>", whose Stop action discards everything. When the Transcript is written, it posts "Transcript ready." with a Show action. A native Settings window opens with a General tab whose first control is "Transcribe Meetings automatically". With that setting off, Detection only offers: Transcribe, Transcribe in <language> or Never, with a 60 s timeout and a 10 min mute after a decline. On first launch Carbon only shows the system permission prompts, with no onboarding. Spec: UI (Notifications, First launch, Settings › General), and the offer rules in Detector.

**Blocked by:** 03 (Auto-start and auto-stop on microphone Detection).

**Status:** ready-for-agent

- [ ] Start notification: title "Transcribing in <language>", body "<title> · <Provider>". The Stop action is destructive and discards the captured audio.
- [ ] Offer notification: title "<title>", body "<Provider> is using the microphone.", actions Transcribe, Transcribe in <language> and Never.
  - It times out after 60 s.
  - Declining mutes that app for 10 min.
  - Never adds the app to the person's Ignored Apps.
- [ ] "Transcript ready." notification with a Show action that opens the Meeting; until ticket 08 lands, Show reveals the file in Finder.
- [ ] The Settings window (⌘,) has a General tab with the auto-transcribe toggle and its consent footnote, written as in the spec.
- [ ] First launch asks Notifications, Calendar full access, Microphone and System Audio Recording in a row, then registers launch at login.
- [ ] Detector tests cover offer mode: the timeout, the 10 min mute and "Never".
