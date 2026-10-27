# Audio capture probe across meeting apps

Type: prototype
Status: resolved
Blocked by:
Assignee: alexandre

## Question

What does a Core Audio process tap targeting a meeting app's bundle (macOS 26 `bundleIDs`) actually capture for Chrome, Safari, Zoom and Teams, versus a global system-audio tap? Specifically: are browser helper processes (Chrome Helper, WebKit GPU) covered, how does an empty/denied tap show up, what sample rates arrive (speakers vs AirPods/HFP, mid-recording device switch), and which processes report `IsRunningInput` during a call? Outcome: the tap strategy and the "silent tap → fallback" rule for v1. Build a throwaway CLI probe (inspired by Omi's, see "How local meeting transcribers capture and detect meetings").

## Assets

- Probe: [`prototypes/audio-capture-probe/`](../prototypes/audio-capture-probe/README.md) (throwaway CLI; logs and WAVs in `~/CarbonProbe/`)
- Research: [Process tap findings, verified against sources](../../../docs/research/process-tap-findings-verification.md) (all seven probe claims confirmed; three rule changes)
- Research: [Which processes carry call audio in native Zoom and Teams](../../../docs/research/native-meeting-app-audio-processes.md) (helper bundle IDs, mic holders, virtual drivers, idle mic; ends with a probe checklist)

## Progress (2026-10-27, first session)

Paused before real-call measurements; the human could not run the call protocol that session. Next session: start from the protocol in the probe README, Chrome first.

Observed so far (one solo Meet-in-Chrome run, AirPods, plus `afplay` smoke tests):

- An empty tap (no process matches) gets **no IO callbacks at all**, not zero-filled buffers.
- A tap that gets callbacks at full rate but **exact digital zeros** for the whole run is likely a missing System Audio Recording grant for the launching terminal. Unconfirmed: the same global tap captured `afplay` when launched from another terminal. Confirm which terminal ran the Chrome test and whether it was granted.
- `bundleIDs = ["com.google.Chrome"]` got zero callbacks while Chrome was in a Meet. Call audio and the mic sit in `com.google.Chrome.helper` ("Google Chrome Helper (Aperitif)"), which held both input and output. Unconfirmed whether the bundle tap is empty because of the helper, or was also hit by the permission issue. Rerun with `com.google.Chrome.helper` as the bundle ID too.
- `afplay` reports no HAL bundle ID, so prefix matching also checks the executable path.
- The capturing process itself shows `IsRunningInput = true` once a tap runs, so Detection must ignore Carbon.
- AirPods in a call: the input runs at 24 kHz (HFP), and the output also dropped to 24 kHz. The taps still deliver 48 kHz.

## Run 1: Meet in Chrome, built-in speakers (2026-10-27, `~/CarbonProbe/2026-10-27T20-49-47Z/`)

Run from a terminal confirmed to hold System Audio Recording (global tap captured `afplay` just before).

- `bundleIDs = ["com.google.Chrome"]`: **zero callbacks** for 96 s with permission granted. The exact bundle ID does not cover the helper; confirmed, not a permission artefact.
- Prefix tap (`com.google.Chrome` + two `com.google.Chrome.helper` processes): far-side voice at about −30 dBFS, frame for frame the same as the global tap. Helper coverage is what makes Chrome work.
- Mic in use: `com.google.Chrome.helper` (Aperitif) holds input and output for the whole call; `com.apple.CoreSpeech` (`corespeechd`) grabbed input twice for 1–5 s mid-call. Detection must ignore it, and Carbon itself.
- When nobody on the far side speaks, the tap still gets full-rate callbacks of **exact digital zeros**. So "full rate, all zeros" alone does not prove a missing permission; run 6 has to tell the two apart.

## Run 2: Safari, YouTube video on built-in speakers (2026-10-27, `~/CarbonProbe/2026-10-27T20-54-16Z/`, `…20-55-04Z/`)

A video stood in for Meet (the human is not signed in on Safari): the question is which process renders Safari's audio, which is the same for any media.

- `com.apple.Safari` exact bundle: zero callbacks; prefix `com.apple.Safari` matches **no process at all**.
- Audio is rendered by `com.apple.WebKit.GPU` (two instances running); a `com.apple.WebKit` prefix tap captured it, identical to the global tap.
- The WebKit GPU process carries no Safari bundle ID. The prefix tap therefore also took the GPU process owned by **Copper** (another WKWebView app): any WebKit app's audio would leak into the Them track.
- The responsible PID (`responsibility_get_pid_responsible_for_pid`, a private libsystem symbol) resolves each GPU process to its owner: `61776 → Safari`, `53476 → Copper`, `42363 → PasswordsMenuBarExtra`. Owner-based matching is precise; the cost is relying on a private symbol (fine for Developer ID distribution, fragile across OS updates).
- Mic use in a Safari call not measured; Chrome's run covers the Detection side.

## Run 5: Meet in Chrome, built-in speakers → AirPods mid-call (2026-10-27, `~/CarbonProbe/2026-10-27T21-01-02Z/`)

- Default output and input switched to AirPods at 48 s (input 24 kHz HFP). Prefix and global taps **kept running at 48 kHz with no gap** (one dip to ~45k frames/s in the switch second) and kept capturing the far side afterwards (−28 dBFS at 80 s). No restart needed on a device switch.
- Stopping took ~8 s after the switch (vs ~6 s before); slow but no hang.
- `corespeechd` toggled input on/off a dozen times during the call (1–7 s each) until the AirPods connected: a frequent false positive Detection must ignore by name.

## Run 6: denied permission (skipped)

Not measured, by decision: documented (Apple forum 756783, AudioCap) that a tap without System Audio Recording delivers silence with no error.

## Answer

Resolved 2026-10-27, measured on Chrome and Safari, Zoom and Teams from research only (see Assets).

**Tap strategy for v1**

- Carbon taps **every audio process whose owner is the Meeting App**, not a bundle ID: an exact `bundleIDs` tap misses Chrome's helpers, Safari's WebKit GPU process and Zoom's `us.zoom.*` helpers. Owner = responsible PID (`responsibility_get_pid_responsible_for_pid` via `dlsym`, as FineTune and pasrom ship), falling back to the `.app` path when the Meeting App is not its own responsible party. Validate from the signed app, never from a terminal (the terminal becomes the responsible process).
- When a Meeting App process appears or goes, Carbon **updates `kAudioTapPropertyDescription` on the running tap** (no gap) instead of rebuilding it. Process object IDs are never cached: Core Audio reuses them.
- The tap-only aggregate survives a default output switch (speakers → AirPods HFP) at 48 kHz with no restart. Carbon rebuilds the aggregate and the mic capture only when the device list changes (the Zoom and Teams virtual drivers add and remove devices mid-call).
- The mic is captured separately as the Me track.
- Accepted for v1: other tabs of the same browser (or other audio of the Meeting App) land in the Them track; it cannot be isolated below the process without a browser extension, which is out of scope.

**Silent tap → fallback rule**

- **No callbacks** is only meaningful while a Meeting App process reports `IsRunningOutput`: an empty tap documentedly waits for first audio (`AudioHardware.h`). If the Meeting App outputs audio and the tap has had no callbacks for 5 s, Carbon re-resolves the processes, then falls back to a global tap excluding Carbon.
- **Full-rate exact zeros** are normal silence (nobody speaking): no action. A tap that breaks after starting shows up the same way, so it cannot be caught from audio.
- **Permission** is checked up front (private `TCCAccessPreflight("kTCCServiceAudioCapture")`, as AudioCap, FineTune and Hyprnote do) before each Meeting, never inferred from audio.

**Handed to Detection** ("Detection and auto-stop rules on real usage")

- Ignore Carbon itself and `com.apple.CoreSpeech` (`corespeechd` toggled input a dozen times per call); don't count CoreSpeech when deciding a Meeting ended.
- Zoom may keep the mic between calls and Teams sometimes holds it idle: "Meeting App holds the mic" alone must not start a Meeting for them.

**Not measured, to confirm in the signed app:** which Zoom and Teams process carries the call (sources disagree for Teams), whether "share sound" duplicates audio, and the unverified `kAudioDevicePermissionsError` permission tip.
