# How local meeting transcribers capture and detect meetings

Type: research
Status: resolved
Blocked by:

## Question

How do existing on-device meeting transcribers capture audio, detect meetings, auto-stop and handle echo on macOS?

## Answer

Open-source tools use a global Core Audio tap; Granola/Notion use Screen Recording permission. Detection everywhere is mic-in-use + calendar (Hyprnote: `DeviceIsRunningSomewhere` listener + 1 s per-process poll). Pitfalls: browser audio comes from helper processes, muting may release the mic, Zoom holds the mic between calls, a tap without permission returns silent zeros with `noErr`, AirPods force HFP, tap sample rate follows the output device. Details: `docs/research/local-meeting-capture.md`.
