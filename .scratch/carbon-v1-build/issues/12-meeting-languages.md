# 12: Meeting Languages: choose, default, switch mid-Meeting

**What to build:** in Settings › Languages the person checks the Meeting Languages they use and picks a default; Carbon downloads and reserves each one. While live, the person can switch the Meeting Language from the menu bar submenu or from a "Switch to <language>" action on the start notification. The whole Meeting is then re-transcribed from the start in the new language. Outside a Meeting, the submenu sets the default for the next one. Spec: Modules (Transcriber), UI (Menu bar menu, Notifications, Settings › Languages).

**Blocked by:** 04 (Start notification, offer mode and the Settings window).

**Status:** ready-for-agent

- [ ] The Languages tab lists the locales SpeechTranscriber supports, with English and French variants first. A checkbox per language, a "Default language" picker, and a download state per row ("Downloading…" / "Ready").
- [ ] Carbon calls `AssetInventory.reserve` for every checked locale. It checks the asset status when a Meeting starts and downloads the asset again if needed.
- [ ] Switching mid-Meeting starts a new analyzer pair that first takes the recorded CAF files in batch, then continues live. The file has no gap and no text in the old language.
- [ ] The start notification shows one "Switch to <language>" per other checked language.
- [ ] The menu bar's Meeting Language submenu marks the current language with a check.
- [ ] Recorder test: a language switch with a replayed Transcriber produces a file written entirely from the new-language words.
