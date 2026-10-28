# 03: Auto-start and auto-stop on microphone Detection

**What to build:** Carbon notices a Meeting without any click. Say a browser or a native call app holds the microphone for 15 s. If that app is not an Ignored App, Carbon starts a Meeting. It taps every audio process owned by that Meeting App, and it ends the Meeting once the mic has been released and 10 minutes have passed in silence. This ticket brings in the pure Detector state machine, the SignalSampler adapter, the vendor table and the per-app tap. Spec: Modules (Detector, SignalSampler, Vendor table, Capture); the rules come from "Power assertions as a Detection signal" (`.scratch/carbon-v1/issues/17-power-assertions-as-detection-signal.md`) and "Audio capture probe across meeting apps" (`issues/05`).

**Blocked by:** 02 (Me / Them Transcript with the full Turn rules).

**Status:** ready-for-agent

- [ ] SignalSampler lists processes through `kAudioHardwarePropertyProcessObjectList`. It uses property listeners on `IsRunningInput` / `IsRunningOutput`, with a 1 s poll as backstop, and never caches process object IDs.
- [ ] SignalSampler resolves each process to its owning app through the responsible PID (`dlsym`), falling back to the outermost `.app` path.
- [ ] Carbon itself and `com.apple.CoreSpeech` are always ignored. The vendor table ships the initial Ignored Apps list and the never-ignored list.
- [ ] Mic held 15 s → `start`. Mic released + 10 min of silence → `end`. Manual Stop always wins, and a manual start follows the same stop rules.
- [ ] The tap targets every process owned by the Meeting App and updates `kAudioTapPropertyDescription` live when a helper appears or goes.
- [ ] The tap aggregate and the mic capture are rebuilt only when the device list changes.
- [ ] Fallback: the Meeting App reports output but the tap has had no callbacks for 5 s → Carbon re-resolves the processes, then switches to a global tap that excludes Carbon.
- [ ] Each unmatched mic holder is written once to the diagnostic log.
- [ ] A Detector test table covers each mic rule: the 15 s threshold, Ignored Apps, CoreSpeech never counting as a release, the 10 min silence stop.
- [ ] A Recorder test plays a scripted mic-holder sequence and ends with exactly one file.
