# 13: Crash recovery and Keep audio

**What to build:** if Carbon or the Mac dies mid-Meeting, the next launch finishes that Meeting from the audio already on disk, posts "Recovered "<title>" after Carbon quit unexpectedly." and writes the file as usual. Also, "Keep audio after transcribing" (Settings › General, off by default) saves each Meeting's audio as a stereo `.m4a` next to its Markdown file. Spec: "Recovery after a crash", Library (Keep audio).

**Blocked by:** 07 (Speaker A/B/C from offline diarization, with the Me / Them fallback).

**Status:** ready-for-agent

- [ ] At launch, each `InProgress/<id>/` folder is batch-transcribed in the Meeting Language saved in `state.json`, then goes through the normal end of a Meeting: diarization, Library write, cleanup. The end time is the end of the recorded audio.
- [ ] Unreadable audio is discarded, with a notification.
- [ ] Recovery attempts are counted in `state.json`. After two crashes during recovery, the folder moves to `InProgress/Failed/` and Carbon stops retrying.
- [ ] Keep audio: Me on the left, Them on the right, AAC `.m4a` with the same slug. Its path goes in `meetings.json` `audio`, and Delete trashes it too.
- [ ] Recorder test: kill the Meeting between flushes, relaunch with the same folder, get exactly one file covering the flushed audio.
