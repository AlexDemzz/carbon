# 17: HITL: release credentials and the first signed release

**What to build:** the steps only the author can do, then the first real release. They cover what ticket 16 could not:
- the Developer ID Application certificate;
- the App Store Connect API key for notarization;
- the Sparkle EdDSA key pair;
- the scoped Cloudflare token;
- all of them set as GitHub secrets on `AlexDemzz/carbon`.

Then tag `v0.1.0` (the first release is v0.1.0, not v1.0.0) and check that https://carbon.alexandrejoly.me/download gives a DMG that opens with no Gatekeeper warning and updates through Sparkle. Nothing else is blocked on this ticket. Mirrors the "Release secrets" item in `.scratch/carbon-v1/morning-checklist.md`.

**Blocked by:** 16 (Sparkle updates, the release Action and the download Worker).

**Status:** HITL (credentials done; first release pending)

**Progress (2026-10-28):** all release secrets are set on `AlexDemzz/carbon`: `DEVELOPER_ID_P12`, `DEVELOPER_ID_P12_PASSWORD`, `NOTARY_KEY_P8`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `DEVELOPMENT_TEAM`, `SPARKLE_ED_PRIVATE_KEY`, `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`. The R2 bucket `carbon-releases` exists. The Sparkle public key is `SUPublicEDKey=DmKfoKmWRW4yVkZNN0nq1w3x4uu6e/qkz5YXE1zN+ZE=`, committed in the app's Info.plist by ticket 16. The app's marketing version is 0.1.0.

**First tag run (v0.1.0):** failed at "Archive and export with Developer ID": the command-line `CODE_SIGN_IDENTITY` also reaches the SPM resource bundle targets (`CarbonCore_CarbonCore`, `FluidAudio_FluidAudio`), which default to automatic signing, so Xcode reports conflicting provisioning settings. Fix: pass `CODE_SIGN_STYLE=Manual` alongside it. The keychain step now also imports Apple's Developer ID G2 intermediate, since the `.p12` holds only the leaf (in a keychain of its own it gives 0 valid identities).

Local proof on the author's Mac: the archive with the fix gets past the provisioning check and reaches the Developer ID signature of the resource bundles. The `.p12` imports into a CI-style temporary keychain and gives a valid identity once the intermediate is there. The signature itself could not be proven locally: `codesign` fails on this Mac for every identity (Developer ID, Apple Development, iPhone Distribution), even on `/bin/echo` (`errSecInternalComponent`, "unable to build chain to self-signed root"), a machine issue. The unsigned Release build, `make-dmg.sh` (`hdiutil verify` valid) and the `sign_update` binary all check out.

- [x] The Developer ID Application certificate is exported as a `.p12` and stored as `DEVELOPER_ID_P12` and `DEVELOPER_ID_P12_PASSWORD`.
- [x] The App Store Connect API key is stored as `NOTARY_KEY_P8`, `NOTARY_KEY_ID` and `NOTARY_ISSUER_ID`.
- [x] Sparkle keys are generated, the private key is stored as `SPARKLE_ED_PRIVATE_KEY`, and the public key is committed as `SUPublicEDKey`.
- [x] `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` are set, `DEVELOPMENT_TEAM` too, and the R2 bucket `carbon-releases` exists.
- [ ] `CLOUDFLARE_API_TOKEN` has the permissions the release Action now needs, since it deploys the release Worker from `worker/` (`wrangler deploy`) before the R2 upload: **Workers Scripts Edit** (account), **Workers Routes Edit** (zone `alexandrejoly.me`) and **Workers R2 Storage Edit** (account). Check or widen the token before tagging.
- [ ] Tagging `v0.1.0` runs the Action green, including the release Worker deploy (Worker `carbon-releases`, routes `carbon.alexandrejoly.me/download`, `/appcast.xml`, `/releases/*`). `spctl --assess` accepts the downloaded DMG's app, and the website button downloads it. Tags pushed once the GitHub Release step is merged also get a GitHub Release with the DMG and the tag annotation as notes; the v0.1.0 run predates it, so its GitHub Release is made by hand if wanted.
- [ ] A `v0.1.1` tag is offered to the installed `v0.1.0` by Sparkle and installs.
