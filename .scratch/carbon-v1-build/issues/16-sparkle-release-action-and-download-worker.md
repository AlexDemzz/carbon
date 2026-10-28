# 16: Sparkle updates, the release Action and the download Worker

**What to build:** everything in the release pipeline that runs without the author's credentials.
- **App**: Sparkle with "Check for Updates…" and "Check for updates automatically".
- **Release Action** (in the carbon repo), on `v*` tags: build, sign, notarize, make the DMG, sign it for Sparkle, write the appcast, upload to R2.
- **Download Worker**: the existing `carbon` Worker in the alexandrejoly.me monorepo serves `/download`, `/appcast.xml` and `/releases/*.dmg` from the R2 bucket `carbon-releases`.

Without the secrets, the Action runs a dry-run path: an unsigned build plus the tests. Spec: "Distribution and release pipeline", Modules (Updater).

**Blocked by:** 01 (Manual Meeting from the menu bar to a Markdown file).

**Status:** done

- [x] Sparkle 2 with `SPUStandardUpdaterController`. `SUFeedURL` is `https://carbon.alexandrejoly.me/appcast.xml`, with a placeholder for `SUPublicEDKey` until ticket 17. The menu bar menu gets "Check for Updates…", and Settings › General gets the automatic-check toggle.
- [x] Versioning: the tag sets `CFBundleShortVersionString`, and the run number sets `CFBundleVersion`.
- [x] The Action runs these steps in order:
  1. temporary keychain import;
  2. archive and Developer ID export;
  3. `CarbonCore` tests;
  4. `hdiutil` DMG with the app and an Applications symlink;
  5. sign, `notarytool --wait` and staple;
  6. `sign_update`;
  7. regenerate the appcast with release notes from the tag annotation;
  8. upload in the order DMG → `appcast.xml` → `latest.json`.

  When secrets are absent, every signing step is skipped and the run says so.
- [ ] The R2 bucket `carbon-releases` is created with `wrangler`. *Deferred to ticket 17 (needs the author's Cloudflare account): `pnpm exec wrangler r2 bucket create carbon-releases` from `apps/carbon`.*
- [x] The `carbon` Worker gets the `RELEASES` binding and three routes handled ahead of the site:
  - `/download` → 302 to the file named in `latest.json`, `no-store`;
  - `/appcast.xml` → `application/rss+xml`, `max-age=300`;
  - `/releases/<name>.dmg` → streamed, `Range` supported, attachment, immutable, 404 for unknown names.
- [x] Worker tests (Vitest + Miniflare with a local R2) cover the redirect, the appcast content type, a range request and a 404.
- [ ] The Worker is deployed, with the site's `DOWNLOAD_URL` unchanged. Until a first release, `/download` without a `latest.json` returns 404. *Built and tested (404 without `latest.json` is covered, `DOWNLOAD_URL` unchanged, `wrangler deploy --dry-run` shows the `RELEASES` binding); the deploy itself is deferred to ticket 17.*

## Notes

- Worker code: alexandrejoly.me monorepo, branch `carbon/releases` (off `AlexDemzz/carbon-landing`, since `apps/carbon` isn't on `master` yet), worktree `/Users/alexandrejoly/Documents/git-repositories/alexandrejoly.me-worktrees/carbon-releases`. `src/server.ts` answers the routes from `src/lib/releases.ts` before TanStack Start. Tests use `wrangler`'s `getPlatformProxy` (Miniflare with an in-memory R2 bound from `wrangler.jsonc`): `pnpm --filter carbon test`.
- Appcast: `scripts/release/appcast.py` adds one item on top of the published appcast (plain-text release notes from the tag annotation, `sparkle:version` = run number); a rerun of the same build replaces its item. Tested with `python3 -m unittest` in `scripts/release`.
- `sign_update` comes from the Sparkle SPM artifact the archive already resolved (`build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin`), so it matches the pinned Sparkle 2.10.1.
- `SUPublicEDKey` is the real key the author generated. `SUEnableAutomaticChecks` is on, so Sparkle doesn't ask on the second launch.
- Settings: a minimal Settings scene with only the General tab and the toggle, plus "Settings… ⌘," in the menu; ticket 14 builds the rest of the window around it.
- Dry run: any non-tag run, or a tag run with any secret missing, builds unsigned, runs the tests, makes the DMG (kept as a workflow artifact for 7 days) and posts a notice listing what was skipped.
