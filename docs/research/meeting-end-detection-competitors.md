# How competing recorders detect that a meeting has ended

Researched 2026-10-29. The question: how do other macOS meeting recorders decide that a meeting is **over**, so they can stop recording without the user? The focus is Google Meet in Chrome, which has no native-app power assertion.

This note builds on three earlier notes and does not repeat them:

- [prior-art-minute-meeting-transcriber.md](prior-art-minute-meeting-transcriber.md): pasrom's 15 s assertion end grace, Minute's 120 s + 30 s silence countdown.
- [power-assertions-detection.md](power-assertions-detection.md): Chromium's "WebRTC has active PeerConnections" assertion, plus high-level Hyprnote and OpenOats rules.
- [local-meeting-capture.md](local-meeting-capture.md): capture methods and help-center summaries for Granola, Notion, MacWhisper, Krisp, Jamie and Superwhisper.

Sources are primary only: source code at pinned commits, and vendor help centers and changelogs. Anything I concluded myself is marked **(inference)**. Anything I looked for and could not find in a primary source is marked **unverified**. Help-center pages were read on 2026-10-29. Some Zendesk pages block plain fetches, so I read them through the public Help Center API (`/api/v2/help_center/articles/…json`). The cited URL is still the article's public URL.

Carbon today, for reference:

- **Chrome/Meet:** a Meeting ends after the mic is released, then 10 min of silence on Chrome's audio tap, or 30 s if the matched calendar event is over. Chrome's "WebRTC has active PeerConnections" assertion is seen but ignored.
- **Zoom, Teams and Webex:** call power assertion gone, 15 s grace, then 30 s of silence.

## Sources and pins

| Source | Pin | What it is |
|---|---|---|
| [fastrepl/anarlog](https://github.com/fastrepl/anarlog/tree/a7dadfbb9477177723cab1e140ae06b4e868ecc5) (Hyprnote / Char) | `a7dadfb` | Tauri app. Mic-based detection, Accessibility veto, prompt for browsers |
| [screenpipe/screenpipe](https://github.com/screenpipe/screenpipe/tree/928dd3dad2161ac6ea5610379c303f513009a705) | `928dd3d` | Rust. Continuous capture with a meeting watcher |
| [BasedHardware/omi](https://github.com/BasedHardware/omi/tree/79aadbc2639d504e8139938ebf2aa027e505c512) (desktop/macos) | `79aadbc` | Swift. Mic + title-based meeting detector |
| [moona3k/macparakeet](https://github.com/moona3k/macparakeet/tree/590b6c253bd27bc55723f0e8c8394b64467c09de) | `590b6c2` | Swift. Silence-based auto-stop with a countdown |
| [RecapAI/Recap](https://github.com/RecapAI/Recap/tree/6d3ccf5967bb7857632aad624467a97afe461792) | `6d3ccf5` | Swift. Window-title detection |
| [thewh1teagle/vibe](https://github.com/thewh1teagle/vibe/tree/2ea5ecef989933282fca517d82d4e3128ae5fb0b) | `2ea5ece` | Tauri. Start prompt only |
| [Zackriya-Solutions/meetily](https://github.com/Zackriya-Solutions/meetily) | `main` = `a2cb62e`, PRs #666, #733 | Tauri. No detection on main; two open PRs |
| Vendor help centers | read 2026-10-29 | Granola, Otter, Jamie, Superwhisper, Notion, Krisp, MacWhisper, Fireflies, Fellow, tl;dv, Read.ai, Fathom, Tactiq, BuildBetter, Metal, Attention, MeetGeek, QuickContract |

Link prefixes used below:

- **AN** = `https://github.com/fastrepl/anarlog/blob/a7dadfbb9477177723cab1e140ae06b4e868ecc5/`
- **SP** = `https://github.com/screenpipe/screenpipe/blob/928dd3dad2161ac6ea5610379c303f513009a705/crates/screenpipe-engine/src/meeting_watcher/`
- **OM** = `https://github.com/BasedHardware/omi/blob/79aadbc2639d504e8139938ebf2aa027e505c512/desktop/macos/Desktop/Sources/`
- **MP** = `https://github.com/moona3k/macparakeet/blob/590b6c253bd27bc55723f0e8c8394b64467c09de/Sources/`

## Summary

- **No surveyed tool documents the WebRTC power assertion as an end signal for browsers.** pasrom remains the only one that uses it (prior-art note). No closed-source vendor names any low-level signal.
- **For browser Meet, the dominant end signal is "the browser released the mic"**, followed by a short grace: anarlog 5 s, Omi 8 s, screenpipe 4 s + 20 s. Granola says the same in plain words: "auto-stop relies on detecting when your call app stops using the microphone".
- **A silence timeout is the universal backstop**, and it is long when it is the only signal:
  - Otter 10 min (then a 15 s warning), Granola 15 min, OpenOats 15 min;
  - Jamie: 30 s when combined with mic-off and the calendar, plus 10 min without a calendar event;
  - macparakeet 4 min.
- **The calendar end is used as a corroborating signal, never alone.** Jamie requires "the final quarter of the calendar event" plus mic-off plus 30 s of silence. Granola uses "the scheduled end time … as an additional signal".
- **Browsers are treated more cautiously than native apps.** anarlog **always asks** for browsers ("Did your meeting end?", which auto-stops after 30 s if ignored) but stops native apps directly. screenpipe's UI-scan backend waits 300 s for browsers versus 30 s for apps.
- **The dominant UX is "stop unless the user objects":**
  - a short cancellable countdown or notification: Otter, Superwhisper ("Meeting ending in 9s"), anarlog, macparakeet, Jamie;
  - Jamie's **default** only asks, and never stops on its own;
  - screenpipe, Omi, Granola and Metal stop silently.
- **Browser extensions are not used for end detection in any shipped code I could read.** anarlog had a Meet extension, but no code read its state, and it was deleted in May 2026.
- **Back-to-back calls are the admitted weak spot.** Granola says calls "may be merged into a single transcript". screenpipe and Omi split on a **Meet room-code change**, which only a URL or title can provide.

## Comparison table

"Mic off" = the meeting app (or browser) stopped holding input. "Ask" = a prompt that waits for the user. "Countdown" = it stops unless the user cancels.

### Local-capture tools

| Tool | End signals | Timeouts / grace | Browser Meet specifics | What the user sees | Source |
|---|---|---|---|---|---|
| **Granola** | Mic off for the call app; transcript length; calendar scheduled end; no new audio; sleep | 15 min no new audio | None documented; Meet named only as "call software" | Stops on its own; Resume later | [docs.granola.ai](https://docs.granola.ai/help-center/taking-notes/transcription) |
| **Otter (desktop)** | "detect when a meeting ends"; "No conversation detected in the past 10 minutes" | 10 min no conversation → stops in 15 s | Signal not documented | Notification with **Keep recording**; "End recordings automatically" and "End recording notifications" are separate settings | [help.otter.ai](https://help.otter.ai/hc/en-us/articles/35973988280215-Otter-Desktop-App-Mac-Windows) |
| **Jamie** | All of: mic off, final quarter of calendar event, no speech | Silence 30 s (30 s–5 min); no-calendar failsafe +10 min (5–15) | Not addressed | **Default: asks** ("whether the meeting is over"); opt-in auto-stop with a cancellable countdown | [docs.meetjamie.ai](https://docs.meetjamie.ai/getting-started/auto-stop-recording) |
| **Superwhisper** | "When the call ends" (signal not documented) | ~9 s countdown | Detection works "in the desktop app or the browser" | "Meeting ending in 9s" with End meeting / Keep recording; "asks before it stops" | [record.md](https://superwhisper.com/docs/meetings/record.md), [overview.md](https://superwhisper.com/docs/meetings/overview.md) |
| **Notion AI Meeting Notes** | "meeting-app presence and various audio signals, such as whether audio is active" | Not documented | Not documented | Auto-stops when "you've left the call"; Resume transcription | [notion.com/help](https://www.notion.com/help/ai-meeting-notes) |
| **MacWhisper** | Not documented | Not documented (the 10 s timeout is the *start* prompt's) | Browsers in the supported-apps list | A "Meeting Ended Notification" from which you stop | [docs.macwhisper.com](https://docs.macwhisper.com/article/30-record-meetings) |
| **Krisp** | Note Taker: **unverified**. Speech-analytics recording: a call = Krisp Microphone **and** Krisp Speaker active | 2 h cap "if Krisp cannot determine whether a call is still active" (speech analytics) | Not documented | Note Taker: manual stop documented | [Note Taker](https://help.krisp.ai/hc/en-us/articles/30146816045980-Record-your-meetings-with-Krisp-AI-Note-Taker), [screen recordings](https://help.krisp.ai/hc/en-us/articles/29411333347484-Krisp-AI-Speech-Analytics-Agent-screen-recordings) |
| **Fireflies (desktop)** | Not documented | — | Detects Meet; "supported browser" link detection | Manual stop documented | [guide.fireflies.ai](https://guide.fireflies.ai/articles/6666374717-how-to-record-meetings-without-a-bot-on-the-fireflies-desktop-app) |
| **Fellow (desktop)** | None (manual) | — | Chrome extension **starts** recording on join link | Stop → dialog (Stop & Generate / Continue / Discard) | [help.fellow.ai](https://help.fellow.ai/en/articles/12015496-desktop-botless-recording) |
| **tl;dv (desktop)** | None (manual) | — | — | "When the meeting ends, click Stop Recording" | [intercom.help/tldv](https://intercom.help/tldv/en/articles/14433337-bot-free-recording) |
| **Read.ai (desktop)** | None (manual) | — | — | "Stop recording when the meeting ends" | [support.read.ai](https://support.read.ai/hc/en-us/articles/51486232225555-Capturing-Webex-Meetings-with-Read-Desktop-App) |
| **Fathom (Mac, bot-free)** | **unverified** | — | — | — | [fathom.ai/whats-new](https://www.fathom.ai/whats-new) |
| **BuildBetter Local Recorder** | "meeting ends" (signal not documented); detection uses "mic, apps, and network" and optionally browser URLs | **30 s grace** (default); auto-stop **off** by default | "check browser URLs (requires Automation permission)" | Stops on its own when enabled | [docs.buildbetter.ai](https://docs.buildbetter.ai/pages/Local%20Recorder/settings) |
| **Metal** | "stops automatically when the call ends" (signal not documented) | Not documented | — | Stops on its own | [docs.metal.so](https://docs.metal.so/content/meeting-intelligence/desktop-app.md) |
| **QuickContract** | Meeting app process gone **and** 15 s silence on both streams; browser calls only via mic ≥ 5 s for start | 15 s silence, 10 s countdown | Browser not covered by auto-stop | Countdown with Cancel | [call-detection](https://quickcontract.pages.dev/docs/recording/call-detection.html) |

### Open-source local-capture tools (code read)

| Tool | End signals | Timeouts / grace | Browser Meet specifics | What the user sees |
|---|---|---|---|---|
| **anarlog** | Mic off (per process) → Accessibility veto ("leave call" button) | 1 s poll, 500 ms debounce, 5 s confirm, 10 s AX timeout; network drop: event end + 10 min or 8 min | **Always asks for browsers** | "Did your meeting end? Anarlog will stop listening in 30 seconds." Stops on accept **or** timeout |
| **screenpipe** | Mic-holding process matched to a meeting (browser tab URL via AppleScript / AX); room change; calendar boundary | 4 s stickiness + 20 s ending grace; UI-scan backend: 30 s apps / **300 s browsers** | Meet room change ends immediately | Silent auto-stop |
| **Omi desktop** | Browser holds mic **and** title matches `Meet - xxx-xxxx-xxx` | 8 s off grace; resume window 240 s, or 15 min for the same Meet code | Meet code used for continuity | Silent auto-stop |
| **macparakeet** | Native: app quit (15 s); browser: silence on both channels | 240 s silence + 15 s countdown toast | No browser-specific signal | "This meeting looks finished" countdown |
| **OpenOats** | Mic off and camera off, or no utterance | 15 min since last utterance | — | Auto-stop (prior note) |
| **Minute** | Summed mic + system level below threshold | 120 s + 30 s countdown | — | "Keep recording" countdown (prior note) |
| **pasrom** | Power assertion gone (incl. Chromium WebRTC) | 15 s grace | WebRTC assertion; start asks consent | Silent auto-stop (prior note) |
| **Recap** | None: end handler is a TODO | — | Window titles via ScreenCaptureKit (start only) | Nothing |
| **Vibe** | None: end only hides the start prompt | 600 ms / 5 s debounce | Title match (start only) | Nothing |
| **Meetily PRs** | #666: window title gone; #733: AppleScript tab URL gone | #666: 5 s × 4 misses ≈ 20 s; #733: 10 s, first miss | Title / URL | Stops its own auto-started recordings (unmerged) |

### Bot-based and extension-based tools (end is not a detection problem)

These tools either sit in the call as a participant, or run inside the Meet page. Their "meeting ended" is an event, not an inference, so they are listed for completeness only.

- **Read.ai:**
  - The bot leaves after "no participants joined the meeting within 10 minutes of scheduled start time" and at the plan's maximum length (1 h Free, 4 h Pro/Enterprise, 8 h Enterprise+) ([support.read.ai](https://support.read.ai/hc/en-us/articles/56870728462227-How-do-I-set-up-Zoom-so-Read-can-join-and-record-my-meetings)).
  - With Google Meet native recording, "Read stops recording automatically when everyone leaves the call" ([support.read.ai](https://support.read.ai/hc/en-us/articles/42785087487251-Using-Read-s-Google-Meet-Native-Recording)).
- **Otter, Fireflies, tl;dv, Fathom, Fellow:** their default notetaker is a bot ([Otter](https://help.otter.ai/hc/en-us/articles/35973988280215-Otter-Desktop-App-Mac-Windows), [Fireflies](https://guide.fireflies.ai/articles/6666374717-how-to-record-meetings-without-a-bot-on-the-fireflies-desktop-app), [tl;dv](https://intercom.help/tldv/en/articles/14433337-bot-free-recording), [Fathom](https://www.fathom.ai/whats-new)). Each one's bot-free desktop mode is in the local table above.
- **Tactiq:**
  - It works inside the Meet page through Meet's captions ([troubleshooting](https://help.tactiq.io/en/articles/13863718-how-to-troubleshoot-tactiq-not-activating-in-google-meet)).
  - Its help pages document only manual pause and stop ([pause](https://help.tactiq.io/en/articles/5570498-pause-and-auto-pause)).
  - How it ends a transcript when you leave is **unverified**.
- **Bluedot:** a Chrome extension. I found no primary source on its end handling, so it is **unverified**.

## 1. Closed-source local tools in detail

### Granola

- **Signals:** "when it detects that your call has ended, based on the length of the transcript, whether or not you are still using the call software (e.g Zoom, Teams, Google Meet), and — for calendar-linked meetings — the scheduled end time of the event" ([How transcription works](https://docs.granola.ai/help-center/taking-notes/transcription)).
- **Ad-hoc meetings:** "don't have a scheduled end time, so auto-stop relies on detecting when your call app stops using the microphone. If audio continues — for example, if you keep talking after hanging up — the 15-minute inactivity timeout won't trigger" ([same](https://docs.granola.ai/help-center/taking-notes/transcription)).
- **Backstops:** "when 15 minutes passes without any new audio being detected to transcribe", and "when you put your computer to sleep" ([same](https://docs.granola.ai/help-center/taking-notes/transcription)).
- **OS / admin caveat:** "On macOS versions below 14.2, non-admin users may not get this call-ended signal, so you'll need to click the stop button manually" ([same](https://docs.granola.ai/help-center/taking-notes/transcription)).
  - macOS 14.2 is the Core Audio process-object/tap release ([local-meeting-capture.md](local-meeting-capture.md)).
  - IOKit's assertion-change notification is admin-only ([power-assertions-detection.md §1](power-assertions-detection.md#polling-cost-and-the-private-notification)).
  - Which signal Granola uses below 14.2 is **unverified**. Tying the caveat to either API is my **(inference)**.
- **Back-to-back:** "your meeting app (e.g. Zoom) may keep the microphone active between calls … both meetings may be merged into a single transcript" ([same](https://docs.granola.ai/help-center/taking-notes/transcription)).
- **Meet:**
  - Granola reads Meet participant names via "Accessibility in Google Chrome or the Granola Chrome extension" ([speaker tags](https://docs.granola.ai/help-center/taking-notes/speaker-attribution-google-meet)).
  - Whether either one feeds end detection is **unverified**.
- **UX:** it stops on its own. No "meeting ended?" prompt is documented. A note can be resumed with **Resume** ([same](https://docs.granola.ai/help-center/taking-notes/transcription)).

### Otter desktop

- **End detection:** "Otter can automatically detect when a meeting ends and stop the recording. If you wish to continue recording after a meeting has finished, click **Keep recording** when you see the notification" ([Otter Desktop App](https://help.otter.ai/hc/en-us/articles/35973988280215-Otter-Desktop-App-Mac-Windows)).
- **Two settings:**
  - "End recording notifications: Get reminders when you may have forgotten to stop recording";
  - "End recordings automatically: Let Otter stop recordings when a meeting ends".
  
  The page shows an "Example of recording ending automatically after leaving a meeting" ([same](https://help.otter.ai/hc/en-us/articles/35973988280215-Otter-Desktop-App-Mac-Windows)).
- **Silence backstop:** "No conversation detected in the past 10 minutes: Otter will stop recording in 15 seconds. Click keep recording to continue" ([same](https://help.otter.ai/hc/en-us/articles/35973988280215-Otter-Desktop-App-Mac-Windows)).
- **Signal:** not documented. Google Meet and "Other browser apps" are in the detection list.

### Jamie

The richest published policy ([Auto-stop](https://docs.meetjamie.ai/getting-started/auto-stop-recording)):

- **Conditions, all required:**
  - "Your microphone becomes inactive";
  - "in the final quarter of the calendar event", which stays true after the event ends;
  - "No speech has been detected for at least 30 seconds", configurable from 30 s to 5 min.
- **No calendar link:** an inactivity failsafe adds "a further 5 to 15 minutes (default 10 minutes)" on top. It also applies after the user cancels an automatic stop, "until the conversation resumes".
- **UX:**
  - **Default is "Notification only"**: "Instead of stopping, Jamie shows a notification asking whether the meeting is over", with Stop Jamie and "Don't warn again".
  - "Stop Jamie" mode auto-stops after a countdown that is "a few seconds to cancel", with no exact length published.
- **Browsers:** not addressed.

### Superwhisper

- "When the call ends, Superwhisper shows **Meeting ending in 9s**. Click **End meeting** to stop now, or choose **Keep recording** from its menu" ([Record a meeting](https://superwhisper.com/docs/meetings/record.md)).
- "Either way, Superwhisper asks before it stops a recording" ([Meetings](https://superwhisper.com/docs/meetings/overview.md)). Read together, the "ask" is a 9 s countdown, not a blocking question **(inference)**.
- Detection covers Meet "in the desktop app or the browser". The end signal is not documented.

### Notion AI Meeting Notes

- "If you're using a meeting platform, Notion can detect when you've left the call and automatically stop transcription."
- "To detect when a call ends, Notion uses meeting-app presence and various audio signals, such as whether audio is active" ([Notion help](https://www.notion.com/help/ai-meeting-notes)). This updates [local-meeting-capture.md](local-meeting-capture.md), which recorded "Manual".
- No timeout is documented.

### Krisp

- Krisp captures through its virtual devices. For its call-center speech analytics:
  - "Recording starts when a call begins and stops when the call ends. Only calls where both Krisp Microphone and Krisp Speaker are active are captured."
  - "If Krisp cannot determine whether a call is still active, for example on a persistent connection, recording stops and uploads automatically after 2 hours" ([Agent screen recordings](https://help.krisp.ai/hc/en-us/articles/29411333347484-Krisp-AI-Speech-Analytics-Agent-screen-recordings)).
- For the AI Note Taker, the help page documents only manual start and pause, and "Once a meeting has started, you'll see a call indication bar" ([Note Taker](https://help.krisp.ai/hc/en-us/articles/30146816045980-Record-your-meetings-with-Krisp-AI-Note-Taker)).
- That the Note Taker's call boundary is the same virtual-device activity is my **(inference)**. Its end behavior is **unverified**.

### Others

- **MacWhisper:** stop "from the bottom right side of the MacWhisper main window" or from the "Meeting Ended Notification" ([docs](https://docs.macwhisper.com/article/30-record-meetings)). What triggers that notification is **unverified**.
- **BuildBetter Local Recorder:**
  - "Detect meetings using mic, apps, and network".
  - "Advanced detection: Also check browser URLs (requires Automation permission)", off by default.
  - "Auto-stop when meeting ends", off by default, with a "Grace period: Wait time before stopping (prevents false stops)" defaulting to 30 s ([settings](https://docs.buildbetter.ai/pages/Local%20Recorder/settings)).
- **Metal:** "You can stop at any time, or it stops automatically when the call ends". It needs Screen Recording "to detect and record your meetings" ([docs](https://docs.metal.so/content/meeting-intelligence/desktop-app.md)).
- **Attention:**
  - It detects "by reading window information from Zoom, Meet, or Teams".
  - Documented stops are a network drop and "closing the laptop lid ends the meeting".
  - No call-end detection is documented ([docs](https://docs.attention.com/core-features/desktop-app)).
- **MeetGeek desktop:** detection prompts. Stop behavior is not documented ([quickstart](https://support.meetgeek.ai/en/articles/13745672-meetgeek-desktop-app-quickstart-guide)).
- **QuickContract:** auto-stop needs "The meeting app process is no longer running" **and** "15 seconds of silence is detected across both audio streams", then a 10 s countdown with Cancel ([call detection](https://quickcontract.pages.dev/docs/recording/call-detection.html)).
- **Fireflies, Fellow, tl;dv, Read.ai, Fathom:** see the table. Their bot-free desktop modes document a manual stop, or nothing.

## 2. Open-source tools in detail

### anarlog (Hyprnote / Char)

- **Mic stop event:** per-process `is_running_input` ([AN crates/detect/src/list/macos.rs#L85-L99](https://github.com/fastrepl/anarlog/blob/a7dadfbb9477177723cab1e140ae06b4e868ecc5/crates/detect/src/list/macos.rs#L85-L99)), polled every 1 s ([AN crates/detect/src/mic/macos/mod.rs#L21](https://github.com/fastrepl/anarlog/blob/a7dadfbb9477177723cab1e140ae06b4e868ecc5/crates/detect/src/mic/macos/mod.rs#L21)), with a 500 ms debounce ([AN crates/detect/src/mic/macos/state.rs#L31](https://github.com/fastrepl/anarlog/blob/a7dadfbb9477177723cab1e140ae06b4e868ecc5/crates/detect/src/mic/macos/state.rs#L31)).
- **Confirm (5 s)** ([AN apps/desktop/src/stt/auto-stop.ts#L19-L24](https://github.com/fastrepl/anarlog/blob/a7dadfbb9477177723cab1e140ae06b4e868ecc5/apps/desktop/src/stt/auto-stop.ts#L19-L24); flow at [AN detect-events.ts#L225-L397](https://github.com/fastrepl/anarlog/blob/a7dadfbb9477177723cab1e140ae06b4e868ecc5/apps/desktop/src/stt/detect-events.ts#L225-L397)):
  - It takes a fresh mic snapshot. It aborts if the trigger app is back on the mic. If another meeting app holds the mic, that app becomes the trigger.
  - **Accessibility veto:** if Meet still shows an enabled, visible "leave call" button, it re-arms the 5 s timer ([AN crates/detect/src/meeting_ax/node.rs#L139-L162](https://github.com/fastrepl/anarlog/blob/a7dadfbb9477177723cab1e140ae06b4e868ecc5/crates/detect/src/meeting_ax/node.rs#L139-L162)). This handles a muted user, whose browser may release the mic **(inference)**.
  - **Network drop:** it holds until the event end + 10 min, or 8 min with no event.
- **Browsers always prompt.** `shouldPromptBeforeAutoStopping` returns true for any browser bundle ID ([AN auto-stop.ts#L36-L46](https://github.com/fastrepl/anarlog/blob/a7dadfbb9477177723cab1e140ae06b4e868ecc5/apps/desktop/src/stt/auto-stop.ts#L36-L46)). Native apps are stopped directly.
- **Prompt:**
  - Text: "Did your meeting end?" / "Anarlog will stop listening in 30 seconds." ([AN auto-stop.ts#L165-L212](https://github.com/fastrepl/anarlog/blob/a7dadfbb9477177723cab1e140ae06b4e868ecc5/apps/desktop/src/stt/auto-stop.ts#L165-L212)).
  - Both accept and **timeout** call `stop()` ([AN apps/desktop/src/services/event-listeners.tsx#L190-L217](https://github.com/fastrepl/anarlog/blob/a7dadfbb9477177723cab1e140ae06b4e868ecc5/apps/desktop/src/services/event-listeners.tsx#L190-L217)). So the "ask" is really a 30 s countdown.
  - If the browser takes the mic again, the prompt is cancelled ([AN detect-events.ts#L170-L178](https://github.com/fastrepl/anarlog/blob/a7dadfbb9477177723cab1e140ae06b4e868ecc5/apps/desktop/src/stt/detect-events.ts#L170-L178)).
- **No "event ended → stop" rule.** The calendar end only bounds the network-drop hold.
- **The Meet Chrome extension never drove auto-stop:**
  - It sent `meeting_ended` only on `beforeunload` or on a URL change ([`apps/chrome/entrypoints/meet.content/index.ts` L113-L171 @ acc88e2](https://github.com/fastrepl/anarlog/blob/acc88e2/apps/chrome/entrypoints/meet.content/index.ts#L113-L171)).
  - Its "active" test passes on the `/xxx-xxxx-xxx` URL alone, so the "You left the meeting" screen probably still counted as active **(inference, from the code; not tested)**.
  - No code at either commit reads the native host's `chrome_state.json`.
  - The extension was deleted on 2026-05-10 (commit `f0cc81d`, "cleanup").

### screenpipe

- **Default macOS backend: audio process.** A mic-holding process matched to a meeting; browsers resolve to a meeting URL through AppleScript tab URLs or AX ([SP audio_process/macos.rs#L15-L31](https://github.com/screenpipe/screenpipe/blob/928dd3dad2161ac6ea5610379c303f513009a705/crates/screenpipe-engine/src/meeting_watcher/audio_process/macos.rs#L15-L31)).
- **End:**
  - `STICKY_PROCESS_WINDOW` = 4 s, then `ENDING_GRACE` = **20 s**. Polls every 1 s while active, every 5 s when idle ([SP audio_process/mod.rs#L51-L72](https://github.com/screenpipe/screenpipe/blob/928dd3dad2161ac6ea5610379c303f513009a705/crates/screenpipe-engine/src/meeting_watcher/audio_process/mod.rs#L51-L72)).
  - A different conference-room identity is "an immediate boundary: end the old meeting and start the new one, even when an ended old tab remains visible" (`ROOM_CHANGE_CONFIRM_WINDOW = 0`, same lines).
- **UI-scan backend** (Accessibility call controls): `ENDING_TIMEOUT_BROWSER` = **300 s**, against 30 s for apps, because switching tabs hides the controls ([SP shared/state.rs#L71-L78](https://github.com/screenpipe/screenpipe/blob/928dd3dad2161ac6ea5610379c303f513009a705/crates/screenpipe-engine/src/meeting_watcher/shared/state.rs#L71-L78)).
- **UX:** fully automatic. Base capture is continuous anyway, so an early end costs little there.

### Omi desktop

- **Browser test:** a browser counts as in a call while it holds the mic **and** its title matches the Meet room pattern `^meet\s*[-–]\s*xxx-xxxx-xxx` ([OM ConferencingApps.swift#L80-L98](https://github.com/BasedHardware/omi/blob/79aadbc2639d504e8139938ebf2aa027e505c512/desktop/macos/Desktop/Sources/ConferencingApps.swift#L80-L98)).
- **Off grace:** 8 s, after which capture closes ([OM MeetingDetector.swift#L105](https://github.com/BasedHardware/omi/blob/79aadbc2639d504e8139938ebf2aa027e505c512/desktop/macos/Desktop/Sources/MeetingDetector.swift#L105)).
- **Continuity** ([OM Audio/MeetingCallObservation.swift#L112-L127](https://github.com/BasedHardware/omi/blob/79aadbc2639d504e8139938ebf2aa027e505c512/desktop/macos/Desktop/Sources/Audio/MeetingCallObservation.swift#L112-L127)):
  - `resumeWindow` = 240 s.
  - "A known Meet code survives tab switches and microphone inactivity for at most 15 minutes".
  - "Covers the observed 150s output gap with headroom". This is a field measurement that a live call can go 150 s without output audio.

### macparakeet

- **Native apps:** "app quit" with 15 s grace.
- **Browsers** get no app signal, so they rely on `silenceGraceSeconds = 240` on both channels ([MP MacParakeetCore/Services/MeetingRecording/MeetingAutoStopPolicy.swift#L51-L105](https://github.com/moona3k/macparakeet/blob/590b6c253bd27bc55723f0e8c8394b64467c09de/Sources/MacParakeetCore/Services/MeetingRecording/MeetingAutoStopPolicy.swift#L51-L105)).
- **UX:** a 15 s "This meeting looks finished" countdown toast ([MP MacParakeet/App/MeetingAutoStopCoordinator.swift](https://github.com/moona3k/macparakeet/blob/590b6c253bd27bc55723f0e8c8394b64467c09de/Sources/MacParakeet/App/MeetingAutoStopCoordinator.swift)).

### Recap, Vibe, Meetily

- **Recap:**
  - It detects Meet from ScreenCaptureKit window titles ("meet.google.com", "google meet", "meet -") ([Recap MeetingPatternMatcher.swift#L88-L94](https://github.com/RecapAI/Recap/blob/6d3ccf5967bb7857632aad624467a97afe461792/Recap/Helpers/MeetingDetection/MeetingPatternMatcher.swift#L88-L94)).
  - `sendMeetingEndedNotification()` is a TODO ([Recap RecapViewModel+MeetingDetection.swift#L68-L95](https://github.com/RecapAI/Recap/blob/6d3ccf5967bb7857632aad624467a97afe461792/Recap/UseCases/Home/ViewModel/RecapViewModel+MeetingDetection.swift#L68-L95)).
- **Vibe:**
  - Device-level `DeviceIsRunningSomewhere` plus title match ([Vibe crates/meeting-detect/src/window_title.rs#L10-L12](https://github.com/thewh1teagle/vibe/blob/2ea5ecef989933282fca517d82d4e3128ae5fb0b/crates/meeting-detect/src/window_title.rs#L10-L12)).
  - An end only hides the start prompt; there is no auto-stop ([Vibe desktop/src-tauri/src/meeting_prompt.rs#L58-L74](https://github.com/thewh1teagle/vibe/blob/2ea5ecef989933282fca517d82d4e3128ae5fb0b/desktop/src-tauri/src/meeting_prompt.rs#L58-L74)).
- **Meetily:**
  - `main` still has no detection.
  - Open PR [#666](https://github.com/Zackriya-Solutions/meetily/pull/666) stops after 4 missed 5 s window-title scans.
  - Open PR [#733](https://github.com/Zackriya-Solutions/meetily/pull/733) stops on the first 10 s AppleScript poll without a `meet.google.com/` tab.
  - Both stop only recordings they started.

### Not checked

- FluidVoice, BuilderIO's `call_activity.rs`, Amurex, OpenGranola, Ownscribe and LokalBot were not analyzed.
- Natively's extension reports Meet tabs, with 20 s grace on a tab that disappears. In the files read, that only withdraws a start offer, so whether Natively auto-stops is **unverified**.

## Takeaways for Carbon (inference)

Carbon's Chrome rule (mic off + 10 min silence, or 30 s if the event is over) is **within the market range but at its slow end** for the common case. That case is an ad-hoc or overrunning Meet where the user leaves and keeps working with audio playing. Tools that stop quickly on a browser all key on **mic release + a short grace**, and they add a second signal or a countdown to absorb false positives.

### 1. Signals: use the WebRTC assertion as the end signal for Chrome

- **Primary end signal for Chrome: the "WebRTC has active PeerConnections" assertion released by `Google Chrome`, AND Chrome released the mic.**
  - Carbon already sees the assertion. It drops when the last PeerConnection leaves `connected`/`checking`/`completed` ([power-assertions-detection.md §2](power-assertions-detection.md#2-chromium-webrtc-has-active-peerconnections)), and Meet tears down its PeerConnection when you click Leave.
  - Its weaknesses are **start** weaknesses: it fires on unjoinable pages and data channels. They do not apply to an **end** signal for a Meeting that was already confirmed by the mic and calendar.
  - Requiring both signals also covers the muted user: Chrome may release the mic on mute, but the PeerConnection stays up.
  - pasrom already stops on this assertion with 15 s grace. No surveyed tool has a better browser end signal that needs no extra permission.
  - **Caveat 1:** the assertion is browser-wide. A second WebRTC tab (another call, a Discord or Whereby tab) keeps it held. Then Carbon simply falls back to today's rule. It never stops early.
  - **Caveat 2:** only Chromium browsers take it. Safari and Firefox keep the current mic + silence rule.
- **Do not add a Chrome extension or AppleScript tab polling for end detection now.**
  - anarlog built a Meet extension and never wired it to auto-stop, then deleted it.
  - AppleScript tab URLs (screenpipe, Meetily #733, BuildBetter's opt-in) need the Automation permission per browser.
  - Window titles (Omi, Recap, Meetily #666) only see the **front** tab of each window.
  - Keep these as a later option for **back-to-back splitting**. A Meet room-code change is the only signal that separates two consecutive Meet calls. screenpipe and Omi both rely on it.
- **An Accessibility "leave call" check (anarlog) is a good veto but costs a permission.** Carbon does not ask for Accessibility today. Do not add it for this alone.

### 2. Timeouts

| Case | Proposed rule | Basis |
|---|---|---|
| Chrome, WebRTC assertion was held during the Meeting | Assertion gone **and** mic released for **15 s** → end (no silence wait needed) | pasrom 15 s; screenpipe 4 + 20 s; Omi 8 s; anarlog 5 s |
| Chrome, assertion still held (another WebRTC tab) or never seen | Keep today's rule, but shorten the no-event silence to **5 min** | Otter 10 min, Granola 15 min, macparakeet 4 min, Jamie 30 s + 10 min; Omi measured a 150 s output gap in a live call, so stay well above 150 s |
| Matched calendar event is over | Keep **30 s** silence after mic release (Jamie uses the same 30 s, and needs the last quarter of the event) | Jamie |
| Native apps (Zoom/Teams/Webex) | Keep 15 s grace + 30 s silence | pasrom, Jamie |
| Hard cap | Keep a cap (pasrom 4 h, Krisp 2 h when unsure) | — |

Silence should keep counting both channels, as Minute does, so a talking far end keeps a muted user's Meeting alive.

### 3. Auto-stop vs prompt

- **Recommend a cancellable countdown, which is the market's dominant pattern**, not a blocking question:
  - Otter: 15 s, "Keep recording".
  - Superwhisper: "Meeting ending in 9s".
  - anarlog: 30 s, and stops if ignored.
  - macparakeet: 15 s.
- Proposed for Carbon:
  - **Strong end** (assertion + mic released 15 s, or event over + 30 s silence): end with a **10 s** "Meeting ended — Keep recording" notice. Ignoring it ends the Meeting.
  - **Weak end** (silence-only path): the same notice with a **30 s** window, like anarlog's browser prompt.
  - "Keep recording" should suppress auto-stop until the mic or assertion is re-acquired and released again. That is Jamie's "until the conversation resumes" rule.
- **Avoid Jamie's default (ask, never stop).** A forgotten recording keeps capturing the user's next conversation.
- Avoid silent stops for browsers. anarlog and screenpipe's 300 s browser timeout both show that browser end signals are trusted less.
- **Offer Resume** on a just-ended Meeting (Granola, Notion), so a false stop costs one click rather than a split transcript.

### Hand-run checks before shipping

- `pmset -g assertions` during Meet in Chrome:
  - after **Leave call**, with the "You left the meeting" page still open: is the WebRTC assertion released?
  - while **muted**: is Chrome's mic still held?
  - in a 1:1 call where the other party has left;
  - with a second Meet tab open in the lobby.
- **Arc, Brave, Edge:** confirm the assertion is listed under the browser's main process name.
- **Meet PWA:** confirm the assertion is listed under "Google Chrome", not under the app shim.
