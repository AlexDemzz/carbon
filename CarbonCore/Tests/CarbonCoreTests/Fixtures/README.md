# Fixtures

- `ami-ES2004a-*`: AMI Meeting Corpus, meeting ES2004a (CC BY 4.0, University of Edinburgh and the AMI consortium).
  - `-me-words.json`, `-them-words.json`: live SpeechTranscriber words of both streams, from the transcription-eval prototype (`hyp/st`).
  - `-fallback.md`: the transcript-format prototype's Me / Them sample, rendered from those words by `render.py`.
  - `-me-opening.json`, `-them-opening.json`: the words starting before 40 s.
  - `-me-clip.wav`, `-them-clip.wav`: 6 s of each clean stream (16 kHz mono), from 10 s (Me) and 24 s (Them).
