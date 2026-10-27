# Native spoken-language detection

Type: research
Status: resolved
Blocked by:

## Question

Can Apple frameworks detect the spoken language so the person doesn't pick it?

## Answer

No public API. A private `LanguageDetector` exists in Speech.framework (excluded: private API). Transcribing with the wrong locale yields fluent wrong-language text, so text-based detection fails. Changing locale needs a new transcriber. Led to the manual Meeting Language decision in "Carbon v1 product design". Details: `docs/research/language-detection.md`.
