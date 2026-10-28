# Morning checklist

Steps that need the author. Everything else keeps going without them.

- [ ] **Apple Intelligence model not ready** (blocks "On-device summary quality"): open System Settings › Apple Intelligence & Siri and check the on-device model finished downloading. Overnight, Foundation Models reported `modelNotReady` for 90 minutes and `ModelManagerError 1019`. Once ready, any agent session can run `.scratch/carbon-v1/prototypes/summary-eval/run-all.sh` and finish the ticket AFK.
- [ ] **Release secrets** (needed before the first tagged release, see "Carbon v1 spec" › Distribution): export the Developer ID Application certificate as a `.p12`, create an App Store Connect API key for `notarytool`, then add `DEVELOPER_ID_P12`, `DEVELOPER_ID_P12_PASSWORD`, `NOTARY_KEY_P8`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `SPARKLE_ED_PRIVATE_KEY`, `CLOUDFLARE_API_TOKEN` (R2 write) and `CLOUDFLARE_ACCOUNT_ID` to `AlexDemzz/carbon`'s GitHub secrets.
