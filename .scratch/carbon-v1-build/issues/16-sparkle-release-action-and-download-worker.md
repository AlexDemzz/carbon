# 16: Sparkle updates, the release Action and the download Worker

**What to build:** everything in the release pipeline that runs without the author's credentials.
- **App**: Sparkle with "Check for Updates…" and "Check for updates automatically".
- **Release Action** (in the carbon repo), on `v*` tags: build, sign, notarize, make the DMG, sign it for Sparkle, write the appcast, upload to R2.
- **Download Worker**: the existing `carbon` Worker in the alexandrejoly.me monorepo serves `/download`, `/appcast.xml` and `/releases/*.dmg` from the R2 bucket `carbon-releases`.

Without the secrets, the Action runs a dry-run path: an unsigned build plus the tests. Spec: "Distribution and release pipeline", Modules (Updater).

**Blocked by:** 01 (Manual Meeting from the menu bar to a Markdown file).

**Status:** ready-for-agent

- [ ] Sparkle 2 with `SPUStandardUpdaterController`. `SUFeedURL` is `https://carbon.alexandrejoly.me/appcast.xml`, with a placeholder for `SUPublicEDKey` until ticket 17. The menu bar menu gets "Check for Updates…", and Settings › General gets the automatic-check toggle.
- [ ] Versioning: the tag sets `CFBundleShortVersionString`, and the run number sets `CFBundleVersion`.
- [ ] The Action runs these steps in order:
  1. temporary keychain import;
  2. archive and Developer ID export;
  3. `CarbonCore` tests;
  4. `hdiutil` DMG with the app and an Applications symlink;
  5. sign, `notarytool --wait` and staple;
  6. `sign_update`;
  7. regenerate the appcast with release notes from the tag annotation;
  8. upload in the order DMG → `appcast.xml` → `latest.json`.

  When secrets are absent, every signing step is skipped and the run says so.
- [ ] The R2 bucket `carbon-releases` is created with `wrangler`.
- [ ] The `carbon` Worker gets the `RELEASES` binding and three routes handled ahead of the site:
  - `/download` → 302 to the file named in `latest.json`, `no-store`;
  - `/appcast.xml` → `application/rss+xml`, `max-age=300`;
  - `/releases/<name>.dmg` → streamed, `Range` supported, attachment, immutable, 404 for unknown names.
- [ ] Worker tests (Vitest + Miniflare with a local R2) cover the redirect, the appcast content type, a range request and a 404.
- [ ] The Worker is deployed, with the site's `DOWNLOAD_URL` unchanged. Until a first release, `/download` without a `latest.json` returns 404.
