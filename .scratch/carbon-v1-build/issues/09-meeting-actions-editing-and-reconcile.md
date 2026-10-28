# 09: Meeting actions, the editor window, Local Edits and reconcile

**What to build:** the person can do everything to a Meeting from the context menu and the More menu:
- Copy Path ⇧⌘C, Copy Markdown ⌘C, Reveal in Finder;
- Edit ↩ (also double-click), which opens the Markdown in its own window with Speaker chips;
- color dots;
- Rename… for the title;
- Delete ⌫, which asks first and moves the file to the Trash.

Edits the person makes are kept as Local Edits and never overwritten. Files renamed, moved or deleted in Finder are followed. Spec: UI (Editor window, Menus, Title rename), Library (Local Edit, Reconcile, Delete).

**Blocked by:** 08 (Main window: Meeting list, search and Meeting panel).

**Status:** ready-for-agent

- [ ] Context menu: Copy Path, Copy Markdown, Reveal in Finder, Edit, the color palette, Rename… and Delete. More menu: Copy Path, Copy Markdown, Reveal in Finder, Rename… and Delete.
- [ ] Copy Path copies the absolute path.
- [ ] Delete confirmation: "Delete "<title>"?", with the button "Delete Meeting". The file (and any kept audio) moves to the Trash, and a tombstone is added to `deleted`.
- [ ] Editor window: Save with ⌘S, a prompt on closing with unsaved changes. Each save is a Local Edit.
- [ ] `writtenHash` identifies Local Edits. A title rename rewrites only the frontmatter `title` and keeps the file name.
- [ ] Reconcile runs at launch and on FSEvents:
  - a moved file is found again by its `id`;
  - a missing file becomes a Deleted Meeting;
  - Markdown files with an unknown `id` are ignored.
- [ ] The "Transcript ready." notification's Show action now opens the Meeting in the window.
- [ ] Library tests cover reconcile, surgical writes on a Local Edit and slug collisions.
