# 03: Auto-start and auto-stop on microphone Detection

**What to build:** Carbon notices a Meeting without any click. Say a browser or a native call app holds the microphone for 15 s. If that app is not an Ignored App, Carbon starts a Meeting. It taps every audio process owned by that Meeting App, and it ends the Meeting once the mic has been released and 10 minutes have passed in silence. This ticket brings in the pure Detector state machine, the SignalSampler adapter, the vendor table and the per-app tap. Spec: Modules (Detector, SignalSampler, Vendor table, Capture); the rules come from "Power assertions as a Detection signal" (`.scratch/carbon-v1/issues/17-power-assertions-as-detection-signal.md`) and "Audio capture probe across meeting apps" (`issues/05`).

**Blocked by:** 02 (Me / Them Transcript with the full Turn rules).

**Status:** done

- [x] SignalSampler lists processes through `kAudioHardwarePropertyProcessObjectList`. It uses property listeners on `IsRunningInput` / `IsRunningOutput`, with a 1 s poll as backstop, and never caches process object IDs.
- [x] SignalSampler resolves each process to its owning app through the responsible PID (`dlsym`), falling back to the outermost `.app` path.
- [x] Carbon itself and `com.apple.CoreSpeech` are always ignored. The vendor table ships the initial Ignored Apps list and the never-ignored list.
- [x] Mic held 15 s → `start`. Mic released + 10 min of silence → `end`. Manual Stop always wins, and a manual start follows the same stop rules.
- [x] The tap targets every process owned by the Meeting App and updates `kAudioTapPropertyDescription` live when a helper appears or goes.
- [x] The tap aggregate and the mic capture are rebuilt only when the device list changes.
- [x] Fallback: the Meeting App reports output but the tap has had no callbacks for 5 s → Carbon re-resolves the processes, then switches to a global tap that excludes Carbon.
- [x] Each unmatched mic holder is written once to the diagnostic log.
- [x] A Detector test table covers each mic rule: the 15 s threshold, Ignored Apps, CoreSpeech never counting as a release, the 10 min silence stop.
- [x] A Recorder test plays a scripted mic-holder sequence and ends with exactly one file.

**Notes (implementation):**
- Adapters (SignalSampler, SystemAudioTap, MicrophoneSource rebuild, DiagnosticLog) compile but are not run here: the spec checks them by dogfooding the signed app. The live `kAudioTapPropertyDescription` update, the global-tap fallback via `isExclusive`, and the responsible-PID mapping for Zoom/Teams helpers are unverified on a real call.
- "Silence" = RMS under −50 dBFS (`SoundLevel`), measured on Them when the Meeting has a Meeting App, on Me for a manual Meeting with no app on the mic. Tunable by dogfooding.
- "Once" in the diagnostic log means once per launch (`DiagnosticLog.writeOnce`), log at `~/Library/Logs/Carbon/Diagnostics.log`.
- Detection's Meeting Language is `SpeechTranscriber.supportedLocale(equivalentTo: .current)` until ticket 12. The person's Ignored Apps (`Recorder.ignoredApps`) stay empty until ticket 14 binds Settings.
- Provider: vendor table bundle ID → Provider, else the Meeting App's display name; manual Meetings with no app keep "Unknown".
