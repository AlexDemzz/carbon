# Identify the Meeting Language with a bundled acoustic classifier, once per Meeting

Apple has no public spoken language identification API (docs/research/language-detection.md), so Carbon ships SpeechBrain's VoxLingua107 ECAPA-TDNN classifier (Core ML, 43 MB, Apache-2.0) in the app. When the person checked several Meeting Languages, it scores the first seconds of both streams' speech, restricted to those languages, and decides once: a different winner re-transcribes the whole Meeting through the existing language switch. This beats racing one SpeechTranscriber per candidate language (twice the transcription during the window, more per extra language) and Whisper's language detection (larger, slower, worse on 2 s clips); see docs/research/offline-spoken-language-identification.md.

## Consequences

- The app grows by 43 MB, and the model is loaded only for a Meeting that needs it and let go once its language is decided.
- One decision per Meeting: a real change of language mid-Meeting is not followed, because the switch re-transcribes the whole Meeting in one language.
- The classifier judges accent, not words: English spoken with a strong French accent can be identified as French. The thresholds stay conservative until they are calibrated on recorded Meetings, and the native SpeechTranscriber race remains the candidate tie-breaker.
- A language the person did not check is never identified, and a Meeting whose language stays unclear keeps the language it started in.
- The person's choice from the notification ends identification for that Meeting.
