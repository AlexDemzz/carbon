# What does Carbon cost the Mac while it transcribes?

Measured 2026-10-30 on an M3 Pro (12 cores), macOS 27.0.1, Release builds, on a machine also running headless Chrome, Orca and Figma, so every reading carries a few tenths of a percent of noise. 100% is one core, as in Activity Monitor.

## Verdict

- **Idle, waiting for a Meeting:** about **0.05%** of a core, 5 to 7 threads, a 21 MB footprint at launch. Nothing to fix.
- **Transcribing:** most of the cost is not in Carbon's process. SpeechTranscriber runs its model in Apple's `localspeechrecognition` daemon, which Activity Monitor doesn't count under Carbon. Any public figure has to add it.
- **Before this change**, Carbon and the daemon together cost **about 13%** of a core during a Meeting. **After it, 4.7% in a meeting room and about 6% on a call**, with the same transcript.
- **After the Meeting**, CarbonDiarizer runs for about 5 s per stream, peaks at about 450 MB, and exits.

## Method

A command-line harness built against `CarbonCore` and the app's own `SpeechTranscriberAdapter`, `CoreMLLanguageClassifier` and `CoreMLSpeechGate` runs the real `Recorder`: two live SpeechAnalyzer sessions, the CAF files, the language identification between fr-FR and en-US. Its two audio sources replay the two channels of a recorded Meeting from `~/Carbon` at real-time pace, resampled to 48 kHz: the mic in 100 ms buffers, the call in 10 ms buffers as a process tap delivers them. It needs no microphone or audio permission and plays nothing aloud.

Each run lasts 150 s from 60 s into the recording. The CPU time of every process is read with `ps` before and after the middle 115 s. Not covered: the AVAudioEngine and process tap themselves, the menu bar meter (see `menu-bar-mic-meter-performance.md`), coreaudiod.

## Results

| Recording | Change | Carbon | `localspeechrecognition` | Total |
|---|---|---|---|---|
| Call (`presentation`, 60% of the call channel is digital silence) | before | 5.9% | 7.1% | **13.0%** |
| | no volatile results | 2.8% | 5.0% | 7.8% |
| | + 100 ms feeding | 1.7% | 4.5% | 6.1% |
| | + skip digital silence | 2.2% | 4.5% | **6.8%** (a stretch where the call talks) |
| Meeting room (`meeting-oct-29`, the call channel is 100% zeros) | before | 5.8% | 6.8% | **12.6%** |
| | after all three | 2.2% | 2.6% | **4.7%** |

Silence test, same call recording with its call channel replaced by zeros: the daemon cost 4.65% without skipping, as much as speech, and 2.43% with it.

### Why

1. **`volatileResults` was on, and nothing read them.** The adapter keeps only `isFinal` results. Each volatile result was computed by the daemon, sent over XPC and decoded in Carbon.
2. **The call stream reached SpeechAnalyzer 10 ms at a time**, about 100 `AnalyzerInput`s a second, each waking a Swift task and the daemon. `StreamRecorder` now hands the session 100 ms at a time.
3. **The speech service transcribes zeros at full cost.** In the Library's two Meetings, the call channel was digital silence 60% and 100% of the time: the tap delivers zeros while the call plays nothing, and a meeting room has no call audio at all. After 1 s of it, `StreamRecorder` skips it, and the next buffer carries a `bufferStartTime` so word timings stay on the stream's clock. Only a peak under −80 dBFS counts. A microphone's room never got that low: under −70 dBFS 0% of the time in both recordings.

The CAF files still get every frame, so diarization, recovery and a language switch's replay are unchanged.

### Transcript

Two runs of the same build differ by about 3% of their words, because the live recognizer depends on timing. Every change stayed within that noise: same words count, same turn timestamps. Without volatile results, the transcript differed from the baseline by 1.6% of its words.

## After the Meeting

`CarbonDiarizer` on a 10 min call channel: 5.9 s, 3.9 s of CPU, 463 MB peak. On a 23 min mic channel: 5.3 s, 7.4 s of CPU, 439 MB peak. It runs once per diarized stream, then exits.

## Before quoting a number

Confirm it on a signed Release build during a real call: Activity Monitor's CPU column for Carbon plus `localspeechrecognition`, over a few minutes, and the same for the app being compared. The harness leaves out the capture itself and the menu bar.

## Meeting Language identification from the transcript (ADR 0006)

Measured 2026-10-31 on the same Mac, with the same harness, under the same kind of background load (headless Chrome, other agents), which moved every reading by up to a point from one run to the next: `localspeechrecognition` alone read 1.9–2.8% on the same input.

**Steady state**: `run.sh` on the Meeting room recording (2026-10-29, 11:34), 150 s from 60 s in, French transcribed with en-US also checked. Nothing challenges the language there, so this is what identification costs while it agrees.

| Build | Carbon | localspeechrecognition | Total |
|---|---|---|---|
| main (0.4.0, acoustic classifier, decides in the first seconds) | 1.89, 2.02, 1.15% | 2.59, 2.71, 2.02% | 4.48, 4.73, 3.17% |
| PR #30 before these changes (Silero on every chunk) | 2.97, 1.49% | 2.61, 1.94% | 5.59, 3.43% |
| PR #30 now (gate only when a challenge needs it) | 2.34, 2.28, 1.37, 1.17, 2.22% | 2.68, 2.75, 2.10, 2.00, 2.74% | 5.01, 5.03, 3.48, 3.17, 4.96% |

The three builds overlap within that noise. Earlier the same day, under lighter load, the same recording read Carbon 1.96–2.21% with Silero on every chunk, 1.29–1.57% with the gate run only when needed, and 1.17% with identification off: identification now costs Carbon's process a few tenths of a point at most while nothing challenges.

**Switching**: a 160 s clip of English speech on the mic, call replaced by zeros (`BENCH_SILENT_THEM=1`), starting in fr-FR with en-US checked (2 candidates). One vote, confirmed, switches to en-US about 30 s in; the whole Meeting is then transcribed again in English. CPU over the whole run, sampled every 0.5 s:

| Build | Carbon | localspeechrecognition | Total |
|---|---|---|---|
| PR #30 before these changes | 2.81, 2.97% | 3.26, 3.46% | 6.08, 6.42% |
| PR #30 now | 1.89, 2.01, 1.97% | 3.48, 3.42, 3.41% | 5.37, 5.44, 5.38% |

The confirmation itself (re-transcribing the vote's stretch in en-US) took 0.5–0.6 s and about 1 CPU-s of the speech service in both.
