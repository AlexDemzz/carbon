# Library as Markdown files plus a JSON index

Transcripts live as one Markdown file per Meeting in a visible folder (`~/Documents/Carbon/YYYY/YYYY-MM-DD-slug.md`, YAML frontmatter), and app-only state (Provider and external ids, colors, Local Edit and Deleted Meeting markers) lives in `~/Library/Application Support/Carbon/meetings.json` with timestamped backups. Copper keeps everything in a single `notes.json`, but Carbon's main reader is an AI agent that greps and reads files: a single growing JSON blob with escaped text would be unsearchable and too large to read.
