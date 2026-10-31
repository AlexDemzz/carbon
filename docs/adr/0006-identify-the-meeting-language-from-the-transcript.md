# Identify the Meeting Language from the transcript, all Meeting long

ADR 0005's acoustic classifier (SpeechBrain VoxLingua107 ECAPA) can't identify accented speech: on the maintainer's French-accented English it stayed undecided and the Meeting stayed in fr-FR, and replayed on accented clips it confidently picked the speaker's native language every time. The transcript Carbon already writes got every case right offline (docs/research/text-vs-acoustic-language-identification.md, appendix). So the transcript decides, and the classifier is removed from the app.

On each stream, for the whole Meeting, two signals challenge the current language for another of the checked ones:

- **The lexical vote.** `NLLanguageRecognizer`, constrained to the checked languages, reads each run of 10 final words. A chunk counts for a language at a share of 0.9 or more; 3 of the last 4 chunks counting for another language challenge for it.
- **The rate guard.** Past 20 s of speech, fewer than 1 word per second of speech over the latest 30 s of speech (leaving out the last 5 s of audio, whose words may not be final yet) means the current model doesn't understand what is said. Every other candidate is then tried.

Neither switches on its own. The stretch that made the challenge is transcribed again, from the recorded file, in each candidate; a candidate is confirmed when it writes at least as many words as the current language there (and at least 0.2 per second of speech), and most of its 10-word chunks read as it. The guard keeps the confirmed candidate with the best words per second × share. A confirmed language switches the Meeting as before: the whole Meeting is transcribed again in it.

Silero VAD stays as the speech clock: it measures each stream's speech, so silence, music and noise are never speech the transcript missed.

## Consequences

- The app is 43 MB lighter, and nothing is loaded for identification but the 1 MB speech gate, for every Meeting with two or more checked languages, until it ends.
- A Meeting that changes language halfway is followed: identification never stops, and switching back needs the same evidence as switching away.
- Each challenge costs one re-transcription of its stretch per candidate tried (about 10–30 s of audio). A rejected challenge backs its stream off: 20 s of speech for the vote, 60 s for the guard, doubling with each further rejection until the next switch, up to 8 times, so a Meeting in a language nobody checked isn't transcribed again in every candidate every minute.
- A language the recognizer can't tell apart from another checked one (en-US and en-GB) is never identified: only the first of them counts.
- When nothing confirms, the Meeting stays in the language it started in. A language the person picks ends identification for that Meeting.
- Every vote, guard, confirmation, rejection and switch goes to the diagnostic log with its rates and shares, so the thresholds, set from TTS clips and a few real recordings, can be tuned on real Meetings.
- A model that writes fluent text in its own language at a normal rate, over speech in another, is not caught: the vote reads its text as the current language, and the guard sees a normal rate. Offline, a wrong model on native speech still wrote the true language; this stays a miss rather than a false switch.
