# On-device speaker diarization options

Type: research
Status: resolved
Blocked by:

## Question

Which on-device diarization engine can split the "Them" stream into speakers and provide embeddings for Voice Prints, under a license compatible with a free closed-source app?

## Answer

FluidAudio `OfflineDiarizerManager` (CoreML port of pyannote community-1): Apache-2.0 code, CC-BY-4.0 weights (attribution required), ~22 MB, macOS 14+, published DER 10.6 % on AMI SDM, ~300× real time. 256-d embeddings for Voice Prints, matching by cosine distance implemented in Carbon. No published French meeting DER. Details: `docs/research/on-device-diarization.md`.
