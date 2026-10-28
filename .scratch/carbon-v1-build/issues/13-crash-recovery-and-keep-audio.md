# 13: Crash recovery and Keep audio

**What to build:** if Carbon or the Mac dies mid-Meeting, the next launch finishes that Meeting from the audio already on disk, posts "Recovered "<title>" after Carbon quit unexpectedly." and writes the file as usual. Also, "Keep audio after transcribing" (Settings › General, off by default) saves each Meeting's audio as a stereo `.m4a` next to its Markdown file. Spec: "Recovery after a crash", Library (Keep audio).

**Blocked by:** 07 (Speaker A/B/C from offline diarization, with the Me / Them fallback).

**Status:** done

- [x] At launch, each `InProgress/<id>/` folder is batch-transcribed in the Meeting Language saved in `state.json`, then goes through the normal end of a Meeting: diarization, Library write, cleanup. The end time is the end of the recorded audio.
- [x] Unreadable audio is discarded, with a notification.
- [x] Recovery attempts are counted in `state.json`. After two crashes during recovery, the folder moves to `InProgress/Failed/` and Carbon stops retrying.
- [x] Keep audio: Me on the left, Them on the right, AAC `.m4a` with the same slug. Its path goes in `meetings.json` `audio`, and Delete trashes it too.
- [x] Recorder test: kill the Meeting between flushes, relaunch with the same folder, get exactly one file covering the flushed audio.

**Implementation notes:**

- Live and recovered Meetings share `Recorder.file(_:end:folder:words:)` (diarization, Library create, Keep audio, cleanup). Voice Prints should hook in there so recovery gets them too.
- Recovery runs alongside Detection at launch. It never touches `state`, and it skips the live Meeting's folder. A recovered Meeting's provider comes from the vendor table by the saved `meetingApp` bundle ID, or is the bundle ID itself when the table doesn't know it.
- A Meeting with no flushed audio on either stream (killed in its first 5 s) counts as unreadable: it is discarded, with the notification. A single unreadable stream is treated as silence on that side.
- A recovery that fails without crashing (the transcriber throws, for example) leaves the folder for the next launch and counts as an attempt.
- An unreadable `state.json` sends the folder straight to `InProgress/Failed/`, with "Carbon couldn't recover a Meeting and stopped trying."
- If the `.m4a` can't be encoded, the Meeting is kept without audio.
- Notifications go through a minimal `Notifier` (UNUserNotificationCenter), which ticket 04 may replace. Deferred: not checked on a real crash on device.
