# 08: Main window: Meeting list, search and Meeting panel

**What to build:** Show Carbon (⌥⌘C, global, or the menu bar item) opens the native split window. The sidebar lists Meetings newest first, with a search field. The panel shows the selected Meeting: participant tokens, then the Transcript as "Speaker · 0:19" above each Turn. The window reads the Library through the Library module's observable Meeting list. Spec: UI (Main window, Meeting panel), Library (Search); layout validated in "Main window, menus and notification mock" (`.scratch/carbon-v1/issues/12-main-window-and-menus-mock.md`, prototype `prototypes/ui-mock/`).

**Blocked by:** 01 (Manual Meeting from the menu bar to a Markdown file).

**Status:** ready-for-agent

- [ ] Rows show a color dot, a bold title and grey "Oct 27 at 10:00 AM · 42 min · Dana, Marcus +1", with the full participant list on hover.
- [ ] "Search Meetings" is case- and diacritic-insensitive over title, participants and full text, and shows the first matching line under the row. The index is built at launch.
- [ ] The title bar shows the title and "date · length · Provider · Meeting Language".
- [ ] The toolbar has Edit and More (⋯) as two separate buttons; their actions land in ticket 09.
- [ ] Participants appear as Mail-style tokens: monogram and name, with a menu holding the email, Copy Email Address and New Email.
- [ ] Turns are parsed with TranscriptBuilder's header parser and shown with tabular digits.
- [ ] Show Carbon's global shortcut defaults to ⌥⌘C. The menu bar menu gets Show Carbon.
- [ ] Library tests: search over a fixture folder.
