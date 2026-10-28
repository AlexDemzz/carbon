# 17: HITL: release credentials and the first signed release

**What to build:** the steps only the author can do, then the first real release. They cover what ticket 16 could not:
- the Developer ID Application certificate;
- the App Store Connect API key for notarization;
- the Sparkle EdDSA key pair;
- the scoped Cloudflare token;
- all of them set as GitHub secrets on `AlexDemzz/carbon`.

Then tag `v1.0.0` and check that https://carbon.alexandrejoly.me/download gives a DMG that opens with no Gatekeeper warning and updates through Sparkle. Nothing else is blocked on this ticket. Mirrors the "Release secrets" item in `.scratch/carbon-v1/morning-checklist.md`.

**Blocked by:** 16 (Sparkle updates, the release Action and the download Worker).

**Status:** HITL

- [ ] The Developer ID Application certificate is exported as a `.p12` and stored as `DEVELOPER_ID_P12` and `DEVELOPER_ID_P12_PASSWORD`.
- [ ] The App Store Connect API key is stored as `NOTARY_KEY_P8`, `NOTARY_KEY_ID` and `NOTARY_ISSUER_ID`.
- [ ] Sparkle keys are generated, the private key is stored as `SPARKLE_ED_PRIVATE_KEY`, and the public key is committed as `SUPublicEDKey`.
- [ ] `CLOUDFLARE_API_TOKEN` (R2 write on `carbon-releases` only) and `CLOUDFLARE_ACCOUNT_ID` are set.
- [ ] Tagging `v1.0.0` runs the Action green. `spctl --assess` accepts the downloaded DMG's app, and the website button downloads it.
- [ ] A `v1.0.1` tag is offered to the installed `v1.0.0` by Sparkle and installs.
