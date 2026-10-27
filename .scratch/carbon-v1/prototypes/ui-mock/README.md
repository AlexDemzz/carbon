# Main window, menus and notification mock (PROTOTYPE, throwaway)

Answers the ticket "Main window, menus and notification mock" (`../../issues/12-main-window-and-menus-mock.md`).

Round 1 picked the split window (Meeting list + Meeting panel) over a Copper list and a Spotlight panel. Round 2 picked the transcript layout from the Granola take: "Speaker · 0:19" above each line. The variants and their switcher are gone; the panel now shows the participants, the Summary as notes (Key points, Next steps), then the Transcript. Title, date, length, Provider and Meeting Language sit in the window's title bar; Edit and More (⋯) in its toolbar. There is no inline editing: Edit, ↩, double-click and the context menu all open the editor window. In-memory only: nothing is written to disk, Copy Markdown / Copy Path use the pasteboard, Reveal in Finder opens `~/Documents`.

Round 3 picked Mail-style tokens for the participants above the Summary (over a plain line, a Calendar-style avatar stack and an event-info grid): monogram + name per person, click for the email, Copy Email Address, New Email.

Run: `./run.sh`. It builds with SwiftPM, wraps the binary in `.build/Carbon Mock.app` (menu bar only, ad-hoc signed, so notifications work) and opens it with the main window shown.

To try:

- Copy Path (absolute path of the Markdown file, to paste to an AI agent): first item of the right-click menu and of the panel's ⋯ menu, ⇧⌘C.
- Right-click a row: Copy Path, Copy Markdown, Reveal in Finder, Edit, color palette, Delete (asks first).
- More (⋯) in the toolbar: Copy Path, Copy Markdown, Reveal in Finder, Delete. Only actions on this Meeting.
- Menu bar item: Start Transcribing (when no Meeting is live) starts one by hand.
- Name a Speaker: click a name with a chevron in the Transcript (unnamed ones are blue), or the "Speakers" chips in the editor window. Attendees of the event are offered first, "Other Name…" otherwise; a named Speaker lands in Settings › Voice Prints.
- Menu bar item › Prototype › "Simulate Meeting Detected": with auto-transcribe on, the glyph's dot turns red, a live row appears and the notification "Transcribing in English" shows Stop / Switch to …; with it off, the notification asks to transcribe. "Simulate Meeting Ended" keeps the Meeting, Stop discards it.
- Settings… (⌘,): General, Languages, Permissions, Voice Prints, About.
