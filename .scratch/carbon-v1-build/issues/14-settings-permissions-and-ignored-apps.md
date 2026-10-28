# 14: Settings: General, Ignored Apps, Permissions, About

**What to build:** the rest of the Settings window, in its final layout and copy from the spec.
- **General**: Library folder with "Change…", which moves the whole Library after a confirmation; the Show Carbon shortcut recorder; launch at login.
- **Ignored Apps**: the person's added apps, with + and −.
- **Permissions**: the status of each permission, with "Open System Settings".
- **About**: version, FluidAudio CC BY 4.0 credit, privacy and website links, Reveal Diagnostic Log.

A missing permission also adds "Carbon needs <permission> access…" at the top of the menu bar menu. Spec: UI › Settings (final layout).

**Blocked by:** 04 (Start notification, offer mode and the Settings window).

**Status:** done

- [x] General tab: auto-transcribe, keep audio, the Library folder, the Show Carbon shortcut and launch at login, all with the spec's copy. "Check for updates automatically" is added in ticket 16.
- [x] Changing the Library folder says how many files will move, moves them, and updates `meetings.json`.
- [x] Ignored Apps tab: + opens an app picker, − removes the entry, and the note about built-in entries. Apps added through the offer's "Never" appear here.
- [x] Permissions tab: Microphone, System Audio Recording, Calendar and Notifications, each "Allowed" or "Not allowed" with "Open System Settings". When the private preflight is missing, the status shows "Unknown".
- [x] The menu bar menu's missing-permission item opens this tab.
- [x] About tab: version, the FluidAudio CC BY 4.0 credit with a link, the privacy and website links, and Reveal Diagnostic Log.

**Notes (implementation):**
- The Library move merges into the chosen folder file by file; it refuses (moving nothing) when the folder is inside the Library or already has a file at one of the Library's paths. `meetings.json` paths are relative to the Library folder, so no entry changes; the move reconciles, which rewrites the index only if a file had to be found again. The new folder is saved in UserDefaults `libraryFolder`. "Change…" is disabled while a Meeting is live or finishing.
- Permissions are reread on launch, whenever Carbon becomes active, and every 60 s. Not determined counts as "Not allowed". "Unknown" also offers "Open System Settings".
- Not dogfooded: the System Settings deep links (notably `Privacy_AudioCapture`), the shortcut recorder on non-US layouts, and the Settings layout itself (built, smoke-launched, not looked at).
