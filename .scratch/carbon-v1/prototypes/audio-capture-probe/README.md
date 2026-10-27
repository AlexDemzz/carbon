# Audio capture probe (PROTOTYPE, throwaway)

Answers the ticket "Audio capture probe across meeting apps" (`../../issues/05-audio-capture-probe.md`).

Build once: `swiftc -O probe.swift -o probe`

Run from Terminal (first run asks Terminal for System Audio Recording):

```sh
./probe                         # watch only: who holds mic / output
./probe com.google.Chrome 120   # watch + bundle / prefix / global taps for 120 s
```

Logs and WAVs land in `~/CarbonProbe/<timestamp>/` (outside the repo). `level` lines give frames/s, RMS dBFS and seconds of silence per tap; a tap with no callbacks at all reports `framesPerSec: 0`.

## Protocol

Start the call first (so helper processes exist), then the probe, then talk on the other side for ~30 s with your own mic muted, then unmuted.

| # | Situation | Command |
|---|---|---|
| 1 | Google Meet in Chrome, speakers | `./probe com.google.Chrome 90` |
| 2 | Google Meet in Safari, speakers | `./probe com.apple.WebKit 90` then `./probe com.apple.Safari 90` |
| 3 | Zoom app | `./probe us.zoom.xos 90` |
| 4 | Teams app | `./probe com.microsoft.teams2 90` |
| 5 | Any of the above, switch speakers → AirPods mid-call | same command, 120 s |
| 6 | Denied permission: System Settings › Privacy › Screen & System Audio Recording, turn Terminal off, rerun 1 | `./probe com.google.Chrome 30` |
