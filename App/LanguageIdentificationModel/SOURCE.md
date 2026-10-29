# Language identification model

SpeechBrain's ECAPA-TDNN spoken language classifier trained on VoxLingua107 (107 languages), shipped in the app so identifying the Meeting Language never downloads anything. Carbon loads it from `Carbon.app/Contents/Resources/LanguageIdentificationModel` the first time a Meeting needs it, and lets it go once that Meeting's language is decided. `CarbonCore`'s `LogMel` computes its input; `docs/research/offline-spoken-language-identification.md` says why this model.

- Source: https://huggingface.co/aufklarer/SpeechBrain-ECAPA-VoxLingua107-21M-CoreML at revision `2aa4d715a79e410d5f9aa32bd7a4fc9225bf9eb0`, a compiled Core ML (FP16) conversion of [speechbrain/lang-id-voxlingua107-ecapa](https://huggingface.co/speechbrain/lang-id-voxlingua107-ecapa) at revision `0253049ae131d6a4be1c4f0d8b0ff483a0f8c8e9`. Kept: the `.mlmodelc`, `labels.json` (the output order), `config.json` (frontend parameters and upstream checksums), the upstream `LICENSE` and `README.md`. Left out: `frontend.py` (ported to Swift), `validation.json`, `artifact_manifest.json` and `requirements.txt`.
- Every file was checked against the Hugging Face API at that revision (SHA-256 for LFS files, git blob SHA-1 for the others) before being copied here. The `.mlmodelc` hashes also match the repo's `artifact_manifest.json`.
- License: Apache-2.0, for the conversion and for the SpeechBrain model. See `LICENSE`.

## SHA-256

```
e116932ebc2a9186292c3f83b536c13c89e018695b45d51553dd9dedacf885e3  config.json
f13f0331965a4a402f4308ed80de662f2d55167d77e163406712ba170b92eb35  labels.json
c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4  LICENSE
e857d4d4da443c91e31a9840c17ac3a5d1f131032cceb85a9b66ece0ab36ada9  README.md
9e092f41490e5313e38cb6bcc10ce9fe1ed0bdf5ce33c7c3143dfdc47141c8b7  SpeechBrainECAPAVoxLingua107.mlmodelc/analytics/coremldata.bin
546fd351966c937770a8eb64d86764cd87a65d1f58c74627bb47584eeb20413e  SpeechBrainECAPAVoxLingua107.mlmodelc/coremldata.bin
32a6a3fcb77aae3b32123514e83e0c16e4427e986dc2d23cfdde2a4dba1b81c2  SpeechBrainECAPAVoxLingua107.mlmodelc/model.mil
81fbb61f6706c50e924a2ee2a4fc04e6408276df948117a1c6ac7675c23aac67  SpeechBrainECAPAVoxLingua107.mlmodelc/weights/weight.bin
```
