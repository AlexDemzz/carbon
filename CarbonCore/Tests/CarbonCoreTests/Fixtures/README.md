# Fixtures

- `ami-ES2004a-*`: AMI Meeting Corpus, meeting ES2004a (CC BY 4.0, University of Edinburgh and the AMI consortium).
  - `-me-words.json`, `-them-words.json`: live SpeechTranscriber words of both streams, from the transcription-eval prototype (`hyp/st`).
  - `-fallback.md`: the transcript-format prototype's Me / Them sample, rendered from those words by `render.py`.
  - `-them-diarization.json`: FluidAudio 0.17.7 offline diarization of the Me-muted Them track (threshold 0.6), from the transcript-format prototype, converted to Carbon's `Diarization` JSON.
  - `-diarized.md`: the transcript-format prototype's Speaker A/B/C sample, rendered by `render.py` from those words and that diarization, then with Carbon's speaker changes snapped to sentence ends ("My" at 11:52 and "Is it" at 14:58 moved to the next Speaker).
  - `-renamed.md`: the prototype's `sample-renamed.md`, the diarized sample after naming Speaker B "Sam Rivera", with the same two moves.
  - `-me-opening.json`, `-them-opening.json`: the words starting before 40 s.
  - `-me-clip.wav`, `-them-clip.wav`: 6 s of each clean stream (16 kHz mono), from 10 s (Me) and 24 s (Them).
  - `-me-fbank.json`: the reference log-mel features (60 bands, 101 frames) of the first second of `-me-clip.wav`, from the SpeechBrain frontend in `frontend.py` of [aufklarer/SpeechBrain-ECAPA-VoxLingua107-21M-CoreML](https://huggingface.co/aufklarer/SpeechBrain-ECAPA-VoxLingua107-21M-CoreML/blob/2aa4d715a79e410d5f9aa32bd7a4fc9225bf9eb0/frontend.py) (numpy 2.1.3), rounded to 6 significant digits.
