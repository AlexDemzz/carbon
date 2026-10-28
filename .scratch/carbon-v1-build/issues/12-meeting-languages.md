# 12: Meeting Languages: choose, default, switch mid-Meeting

**What to build:** in Settings › Languages the person checks the Meeting Languages they use and picks a default; Carbon downloads and reserves each one. While live, the person can switch the Meeting Language from the menu bar submenu or from a "Switch to <language>" action on the start notification. The whole Meeting is then re-transcribed from the start in the new language. Outside a Meeting, the submenu sets the default for the next one. Spec: Modules (Transcriber), UI (Menu bar menu, Notifications, Settings › Languages).

**Blocked by:** 04 (Start notification, offer mode and the Settings window).

**Status:** done

- [x] The Languages tab lists the locales SpeechTranscriber supports, with English and French variants first. A checkbox per language, a "Default language" picker, and a download state per row ("Downloading…" / "Ready").
- [x] Carbon calls `AssetInventory.reserve` for every checked locale. It checks the asset status when a Meeting starts and downloads the asset again if needed.
- [x] Switching mid-Meeting starts a new analyzer pair that first takes the recorded CAF files in batch, then continues live. The file has no gap and no text in the old language.
- [x] The start notification shows one "Switch to <language>" per other checked language.
- [x] The menu bar's Meeting Language submenu marks the current language with a check.
- [x] Recorder test: a language switch with a replayed Transcriber produces a file written entirely from the new-language words.

**Notes:**

- First launch checks only the system's language (en-US when SpeechTranscriber lacks it), so nothing else is downloaded until the person checks more languages.
- A row whose download failed says "Couldn't download"; reservations beyond `AssetInventory.maximumReservedLocales` are logged to the diagnostic log, and those languages are still downloaded at Meeting start.
- Not verified on a real Meeting: the switch with live SpeechAnalyzer sessions, the AssetInventory reserve/download flow, and the notification actions were built and smoke-launched only. The Settings tab was never looked at.
- The Languages tab lists every supported locale (English and French first), as this ticket says, not only English and French plus the system's languages as the spec words it.
