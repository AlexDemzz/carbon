# 14: Settings: General, Ignored Apps, Permissions, About

**What to build:** the rest of the Settings window, in its final layout and copy from the spec.
- **General**: Library folder with "Change…", which moves the whole Library after a confirmation; the Show Carbon shortcut recorder; launch at login.
- **Ignored Apps**: the person's added apps, with + and −.
- **Permissions**: the status of each permission, with "Open System Settings".
- **About**: version, FluidAudio CC BY 4.0 credit, privacy and website links, Reveal Diagnostic Log.

A missing permission also adds "Carbon needs <permission> access…" at the top of the menu bar menu. Spec: UI › Settings (final layout).

**Blocked by:** 04 (Start notification, offer mode and the Settings window).

**Status:** ready-for-agent

- [ ] General tab: auto-transcribe, keep audio, the Library folder, the Show Carbon shortcut and launch at login, all with the spec's copy. "Check for updates automatically" is added in ticket 16.
- [ ] Changing the Library folder says how many files will move, moves them, and updates `meetings.json`.
- [ ] Ignored Apps tab: + opens an app picker, − removes the entry, and the note about built-in entries. Apps added through the offer's "Never" appear here.
- [ ] Permissions tab: Microphone, System Audio Recording, Calendar and Notifications, each "Allowed" or "Not allowed" with "Open System Settings". When the private preflight is missing, the status shows "Unknown".
- [ ] The menu bar menu's missing-permission item opens this tab.
- [ ] About tab: version, the FluidAudio CC BY 4.0 credit with a link, the privacy and website links, and Reveal Diagnostic Log.
