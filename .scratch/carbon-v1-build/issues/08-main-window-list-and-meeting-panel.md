# 08: Main window: Meeting list, search and Meeting panel

**What to build:** Show Carbon (⌥⌘C, global, or the menu bar item) opens the native split window. The sidebar lists Meetings newest first, with a search field. The panel shows the selected Meeting: participant tokens, then the Transcript as "Speaker · 0:19" above each Turn. The window reads the Library through the Library module's observable Meeting list. Spec: UI (Main window, Meeting panel), Library (Search); layout validated in "Main window, menus and notification mock" (`.scratch/carbon-v1/issues/12-main-window-and-menus-mock.md`, prototype `prototypes/ui-mock/`).

**Blocked by:** 01 (Manual Meeting from the menu bar to a Markdown file).

**Status:** done

- [x] Rows show a color dot, a bold title and grey "Oct 27 at 10:00 AM · 42 min · Dana, Marcus +1", with the full participant list on hover.
- [x] "Search Meetings" is case- and diacritic-insensitive over title, participants and full text, and shows the first matching line under the row. The index is built at launch.
- [x] The title bar shows the title and "date · length · Provider · Meeting Language".
- [x] The toolbar has Edit and More (⋯) as two separate buttons; their actions land in ticket 09.
- [x] Participants appear as Mail-style tokens: monogram and name, with a menu holding the email, Copy Email Address and New Email.
- [x] Turns are parsed with TranscriptBuilder's header parser and shown with tabular digits.
- [x] Show Carbon's global shortcut defaults to ⌥⌘C. The menu bar menu gets Show Carbon.
- [x] Library tests: search over a fixture folder.

## Notes

- Search is built at launch (`Library.load()`) and kept current by Carbon's own writes. Refreshing it on FSEvents comes with Reconcile in ticket 09.
- When the title or a participant matches, no line is shown under the row (as in the validated mock). A body match far into a long line is cropped to start about 30 characters before it, after "…".
- Frontmatter and `#` headings are not searched: "transcript" or a Provider name match nothing.
- Lengths truncate to the minute, at least "1 min"; an hour or more reads "1 hr 5 min". The Meeting Language shows as its language name ("English").
- The Turn header parser lives in `TranscriptParser.swift` as a `TranscriptBuilder` extension (`turns(inMarkdown:)`), apart from ticket 02's rewrite of `TranscriptBuilder.swift`.
- The global shortcut is a fixed ⌥⌘C through `RegisterEventHotKey`; the recorder in Settings is ticket 14. It hides Carbon when the main window is already key.
- Edit and More are present but disabled until ticket 09. The Summary notes (ticket 18) and Speaker menus (ticket 10) are not in the panel yet.
- Not verified by hand: the window's look, the hotkey and the token menus. The app builds and launches without error.

