# Library as Markdown files plus a JSON index

Transcripts live as one Markdown file per Meeting in a visible folder (`~/Carbon/YYYY/YYYY-MM-DD-slug.md`, YAML frontmatter), and app-only state (Provider and external ids, colors, Local Edit and Deleted Meeting markers) lives in `~/Library/Application Support/Carbon/meetings.json` with timestamped backups. Copper keeps everything in a single `notes.json`, but Carbon's main reader is an AI agent that greps and reads files: a single growing JSON blob with escaped text would be unsearchable and too large to read.

## Amendment, 2026-10-30: `~/Carbon` instead of `~/Documents/Carbon`

The Library's default folder moves from `~/Documents/Carbon` to `~/Carbon`, created without asking. macOS asks permission before an app reads Documents, and on a fresh signing identity that prompt froze Carbon's launch. The home folder's root is not a protected location, so `~/Carbon` needs no prompt and no folder picker, and stays visible to the person and to an agent. A hidden `~/.carbon` was rejected: Finder, Open panels and ripgrep's default walk skip dot folders. Zotero, calibre, Logseq and Superwhisper keep their libraries at the home folder's root too. See [macos-home-root-library](../research/macos-home-root-library.md) and [macos-library-location](../research/macos-library-location.md).

A Library that already has a `meetings.json` stays in `~/Documents/Carbon`, and Settings › Library folder › Change… still moves it anywhere.
