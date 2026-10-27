# Main window, menus and notification mock

Type: prototype
Status: resolved
Blocked by:
Assignee: alexandre

## Question

How should the Copper-inspired UI look and behave in detail: the Meeting row (title, date · duration · participants, color dot), Search, inline and new-window editing of a Transcript, Speaker renaming from attendees, the menu bar menu with the language switcher and recording state, and the start notification with Stop / Switch language? A rough SwiftUI mock to react to.

## Answer

Validated by the author on the mock (2026-10-27), after three rounds. Where it differs from the UI part of "Carbon v1 product design", this answer wins.

- **Main window**: native split view. Sidebar: Search ("Search Meetings": title, participants, full text, with the matching line under the row) and rows (color dot, bold title, "Oct 27 at 10:00 AM · 42 min · Dana, Marcus +1" in grey, full participants on hover), newest first. Rejected: a single Copper list, a Spotlight-style panel.
- **Meeting panel**: title and "date · length · Provider · Meeting Language" in the window title bar; toolbar with **Edit** and **More** (plain "•••", no chevron) as two separate buttons. Body: participants as Mail-style tokens (monogram + name, menu with the email, Copy Email Address, New Email; they wrap), the Summary as notes (Key points, Next steps), then the Transcript with "Speaker · 0:19" above each line (elapsed time, no leading zero hours, tabular digits). Rejected: stacked time gutter, chat bubbles, script with a Speakers sidebar, Granola's notes-only view; plain line, avatar stack and info grid for participants.
- **Editing**: no inline editing. Edit, ↩, double-click and the context menu open the Markdown editor in its own window, with Speaker chips on top.
- **Speakers**: every Speaker except Me shows a chevron and opens a menu of the event's attendees plus "Other Name…"; unnamed ones are blue. Naming one stores a Voice Print.
- **Menus**: context menu = Copy Path ⇧⌘C, Copy Markdown ⌘C, Reveal in Finder, Edit ↩, color palette, Delete ⌫. More (⋯) = Copy Path, Copy Markdown, Reveal in Finder, Delete: actions on the shown Meeting only. Copy Path copies the absolute path, for pasting to an AI agent. Keep on Top and Close are dropped.
- **Delete** asks first ("Delete "<title>"?", button "Delete Meeting") and moves the Markdown file to the Trash.
- **Menu bar menu**: while live, "Transcribing "<title>"", Provider and start time, Stop and Discard; otherwise Start Transcribing on top. Then Show Carbon ⌥⌘C, Reveal in Finder, Meeting Language submenu (during a Meeting it switches the live one; outside, it sets the default for the next), Check for Updates…, Settings… ⌘,, Quit Carbon ⌘Q. Glyph's dot turns red while live.
- **Notification**: "Transcribing in <language>", body "<title> · <Provider>", actions Stop (destructive, discards) and one "Switch to <language>" per other Meeting Language. macOS can't nest a "Switch language ▸" submenu. With auto-transcribe off: "<title>", "<Provider> is using the microphone.", Transcribe / Transcribe in <language>.
- **Default title** without an event uses 12-hour time: "Meeting Oct 23, 9:15 AM".
- **Settings**: General, Languages, Permissions, Voice Prints, About (FluidAudio CC BY 4.0 attribution), roughed out, not reviewed.
- An Apple HIG / accessibility pass (`better-interface`) was applied to the main window: named toolbar controls, secondary rather than tertiary text for contrast, heading traits, a chevron so color isn't the only cue, capped measure. Not verified: VoiceOver, keyboard-only, light mode, Dynamic Type.

## Assets

- Mock: [`prototypes/ui-mock/`](../prototypes/ui-mock/README.md) (throwaway SwiftUI menu bar app; `./run.sh`, split window with Summary + Transcript panel)
