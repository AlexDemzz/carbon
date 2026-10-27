# Real meeting test set

Type: task
Status: claimed
Blocked by:

## Question

Assemble the test set (AFK, no hand-recorded Meetings), following "Public meeting corpora for quality tests":

1. **Public corpora (AFK):** download AMI (EN, headset channels split into Me/Them, abstractive summaries, same-speaker series for Voice Prints), QMSum reference summaries, ICSI (~1 h meetings for Summary timing), SUMM-RE dev/test (FR, per-speaker tracks, word timings) and Simsamu (phone-compressed FR). Pick a small subset per language, convert it to Me/Them tracks with references in one shared layout, and record where it lives (outside the repo).

Optional, only if fully scriptable on this Mac: replay corpus files through a real call for compressed call audio (pasrom's no-account Jitsi replay test, Chrome fake-audio flags), then realign the references by cross-correlation.
