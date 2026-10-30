# Performance benchmark

What Carbon costs the Mac, for the landing page. The numbers are in [`performance.json`](performance.json). Why they moved is in [`../research/transcription-cpu-cost.md`](../research/transcription-cpu-cost.md).

CPU is a percent of one core, as in Activity Monitor: 100% is one core busy.

## Setup

- MacBook Pro, Apple M3 Pro (12 cores), macOS 27.0.1, 2026-10-30.
- Other apps were running (headless Chrome, Orca, Figma), so every reading carries about ±0.5 point of noise.
- Recordings: two Meetings from the author's Library, kept with "Keep audio" (`~/Carbon/2026/*.m4a`, channel 0 = mic, channel 1 = call).
  - **Meeting room**: 23 min, French, the call channel is 100% digital silence.
  - **Call**: 10 min, French, the call channel is digital silence 60% of the time.

## 1. Idle

Carbon running with Detection on, no Meeting, next to superwhisper 3.1.0, which also watches for Meetings.

```sh
ps -o time= -p <pid>                                    # CPU time, before and after 120 s
ps -M -p <pid> | tail -n +2 | wc -l                     # threads
footprint <pid> | grep Footprint                        # memory
top -l 2 -s 20 -pid <pid> -stats pid,cpu,th,idlew       # idle wakeups per 20 s
```

CPU % = CPU time gained ÷ 120 s. Wakeups per second = `idlew` ÷ 20. The Carbon measured was a Debug build that had run for 2 hours, through a Meeting, with windows opened: the worst case for Carbon. A fresh Release build holds 21 MB and 5 threads.

## 2. Transcribing

`scripts/bench` replays a recording through Carbon's real `Recorder`, the app's `SpeechTranscriberAdapter`, and the Core ML language identification, at real-time pace. The mic arrives in 100 ms buffers and the call in 10 ms buffers, as the taps deliver them. It needs no permission and plays nothing aloud.

```sh
scripts/bench/run.sh ~/Carbon/2026/<meeting>.m4a 150 60      # 150 s from 60 s in
BENCH_SILENT_THEM=1 scripts/bench/run.sh <meeting>.m4a       # the call replaced by zeros
```

`run.sh` reads every process's CPU time with `ps` from 20 s into the run to 15 s before its end (115 s), and prints:

- **Carbon**: the Bench process, which runs everything Carbon's app runs while transcribing.
- **localspeechrecognition**: Apple's daemon that runs SpeechTranscriber's model. Activity Monitor doesn't show it under Carbon, but it works only for Carbon here, so the total counts it.

"Before" is `main` at 0.3.1. "After" is 0.4.0 (PR #26). To measure "before" again, check out the four files PR #26 changed (`SpeechTranscriberAdapter.swift`, `StreamRecorder.swift`, `Ports.swift`, `SoundLevel.swift`) at their earlier version.

**Not counted**: the audio capture itself (AVAudioEngine, the process tap), the menu bar meter (measured in `../research/menu-bar-mic-meter-performance.md`), coreaudiod and WindowServer.

**Transcript quality**: compare the `BENCH_OUT` Transcripts word by word. Two runs of the same build already differ by about 3% of their words. Every change stayed within that, with the same word count and Turn timestamps.

## 3. After the Meeting

```sh
ffmpeg -i <meeting>.m4a -af "pan=mono|c0=c1" -c:a pcm_f32le them.caf
/usr/bin/time -l Carbon.app/Contents/MacOS/CarbonDiarizer them.caf out.json
```

CarbonDiarizer needs the app bundle around it, for its models.

## Before quoting a number publicly

- Quote "Carbon + Apple's speech service" for transcription, never Carbon's process alone.
- Say the machine and that 100% is one core.
- Still to measure: Carbon in a real call on a signed Release build, with capture and the menu bar included, and superwhisper while it transcribes.
