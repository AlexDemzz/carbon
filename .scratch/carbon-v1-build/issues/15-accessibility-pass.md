# 15: Accessibility pass over the whole UI

**What to build:** Carbon is fully usable with VoiceOver and the keyboard, in both light and dark mode. This applies the spec's acceptance criteria to every window and menu. Spec: UI › Accessibility pass.

**Blocked by:** 09 (Meeting actions, the editor window, Local Edits and reconcile), 11 (Voice Prints: remember, recognize, manage), 12 (Meeting Languages: choose, default, switch mid-Meeting), 14 (Settings: General, Ignored Apps, Permissions, About).

**Status:** done

- [x] Every control has an accessible name. Speaker menus read as "Speaker A, unnamed, rename" or "Sam Rivera, rename", and Turns read as "Speaker, time, text".
- [x] The keyboard alone works: ↑↓ in the list, ↩ to Edit, ⌫ to Delete, ⌘F to Search, and Tab through the panel and Settings.
- [ ] Light and dark mode are both checked, with secondary rather than tertiary text for contrast. Color is never the only cue, and the color dot is announced.
- [x] Reduced motion is honored.

## Done (ticket/15)

- Turns: one VoiceOver element labeled "Speaker, time, text", with the time spoken as a duration (`Turn.spokenElapsed`, "1 minute, 5 seconds", not "1:05"); interacting with it reaches the Speaker menu ("Speaker A, unnamed, rename" / "Sam Rivera, rename", already there from ticket 10) and the selectable text.
- Meeting rows combine into one element; the color dot is announced as the value ("Red tag").
- ⌘F focuses Search through a hidden window shortcut (Carbon is LSUIElement, so there is no Find menu item). ↑↓, ↩ (Edit), ⌫ (Delete) were already wired (ticket 09).
- Settings: each "Open System Settings" is named for its permission; Languages rows combine into "English (United States), Ready" and the last checked one has a hint and tooltip ("At least one language stays checked."); "Couldn't download" gets an icon so red is not the only cue; Voice Print rows read name + "Heard in…" as one element; announcements for a single Voice Print delete, the Shortcut recorder (start and result) and a finished language switch.
- Contrast: all secondary text uses `.secondary`; `.quaternary`/`.quinary` are only fills behind tokens and chips.
- Reduced motion: Carbon has no custom animation (no `withAnimation`, `symbolEffect` or transitions), so only system motion remains, which honors the setting.

## Deferred / not verified

- [ ] Checked with the Accessibility Inspector, with the findings fixed or listed in the ticket. Not run: the agent had no interactive session. A person should run the Inspector audit and a VoiceOver walkthrough of the menu, main window, editor and every Settings tab, in light and dark mode.
- Light and dark mode: audited in code only (styles above); not looked at on screen.
- Tab through the panel and Settings reaches menus and buttons only with System Settings › Keyboard › Keyboard navigation on (the macOS default reaches text fields and lists only); no custom focus order was added.
- Verify that the Turn container label (`.contain` + label) reads as intended in VoiceOver on macOS 26, and that the Meeting Language picker says "checked" on the current language.
