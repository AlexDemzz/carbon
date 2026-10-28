# 15: Accessibility pass over the whole UI

**What to build:** Carbon is fully usable with VoiceOver and the keyboard, in both light and dark mode. This applies the spec's acceptance criteria to every window and menu. Spec: UI › Accessibility pass.

**Blocked by:** 09 (Meeting actions, the editor window, Local Edits and reconcile), 11 (Voice Prints: remember, recognize, manage), 12 (Meeting Languages: choose, default, switch mid-Meeting), 14 (Settings: General, Ignored Apps, Permissions, About).

**Status:** ready-for-agent

- [ ] Every control has an accessible name. Speaker menus read as "Speaker A, unnamed, rename" or "Sam Rivera, rename", and Turns read as "Speaker, time, text".
- [ ] The keyboard alone works: ↑↓ in the list, ↩ to Edit, ⌫ to Delete, ⌘F to Search, and Tab through the panel and Settings.
- [ ] Light and dark mode are both checked, with secondary rather than tertiary text for contrast. Color is never the only cue, and the color dot is announced.
- [ ] Reduced motion is honored.
- [ ] Checked with the Accessibility Inspector, with the findings fixed or listed in the ticket.
