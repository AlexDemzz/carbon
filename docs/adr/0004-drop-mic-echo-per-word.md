# Drop the call heard back through the mic, word by word

When the call plays on speakers, the mic hears it again and a shared mic's diarization makes Speakers of the call's voices. Carbon now finds those echo clusters after the Meeting (`MicEcho`: a cluster close to a Them voice, or mostly spoken over Them speech) and leaves out each of their words heard while Them speaks, up to 0.25 s after Them stops for the speakers' and mic's latency. Words of an echo cluster heard while Them is silent are someone in the room talking over a quiet call, and go to the nearest real Speaker. This replaces "No echo handling in v1" in ADR-0003: Carbon's mic capture doesn't use Apple's voice processing, so echo reached the Transcript.

## Consequences

- Dropping per word rather than per cluster keeps a room voice the diarizer lumped in with the echo, as long as it doesn't speak over the call.
- Someone in the room who replies within 0.25 s of the call going quiet, or talks over the call, can be dropped with the echo.
- Sentence-end snapping of Speaker changes runs on the written words only, so it never moves an echo word into the Transcript or a real word out of it.
