# Is a Library folder at the home root (`~/Carbon` or `~/.carbon`) normal for a Mac app?

Researched 2026-10-30. This follows [macos-library-location.md](macos-library-location.md), which covers the TCC mechanics, and does not repeat them. The question: Carbon is a non-sandboxed app signed with Developer ID. Can it create its Library (one Markdown Transcript per Meeting, see [ADR-0002](../adr/0002-json-index-plus-markdown-library.md)) at the root of the home folder by default, with no folder picker and no onboarding step, and is that conventional? The options are `~/Carbon` (visible), `~/.carbon` (hidden), or another place that needs no prompt and no picker. An onboarding `NSOpenPanel` was rejected and is not considered here.

Sources are Apple documentation, the apps' own docs, forums and issue trackers, and source code pinned at a commit. Anything I concluded myself is marked **(inference)**. Anything no primary source settles is marked **unverified**.

Pinned clones (shallow, read only):

- Ollama: [`ollama/ollama@8861ada`](https://github.com/ollama/ollama/tree/8861adaa77839c961d3c574232a8865d65a426b6) (2026-10-28)
- Joplin: [`laurent22/joplin@b48e758`](https://github.com/laurent22/joplin/tree/b48e75856d81152c32e71f21075e1c043d9ea922) (2026-10-29)
- Standard Notes: [`standardnotes/app@695dad5`](https://github.com/standardnotes/app/tree/695dad5d73f6607a56dd0ba4d78a290a7016ea67) (2026-10-27)
- Zettlr: [`Zettlr/Zettlr@ecb7164`](https://github.com/Zettlr/Zettlr/tree/ecb71641be41e51a1fa013c180f1a04dd964f688) (2026-10-29)
- Meetily: [`Zackriya-Solutions/meeting-minutes@a2cb62e`](https://github.com/Zackriya-Solutions/meeting-minutes/tree/a2cb62e827da7ef59f65064c97233efb2313878e) (2026-09-10)
- Zotero: [`zotero/zotero@212a7d6`](https://github.com/zotero/zotero/tree/212a7d6a585d1209bc4e698a904490205f139500) (2026-10-29)
- calibre: [`kovidgoyal/calibre@dda26ee`](https://github.com/kovidgoyal/calibre/tree/dda26ee1702ba4b8807d1b9826ae3c1e84fe0e68) (2026-10-29)
- ripgrep: [`BurntSushi/ripgrep@91f5d22`](https://github.com/BurntSushi/ripgrep/tree/91f5d22ef48bde459d90a8c7dbeab416e97d0f2b) (2026-10-27)
- Logseq and Anarlog: pinned in [macos-library-location.md](macos-library-location.md).

## Short answer

| Option | Who does it by default | Apple's position | Agent can grep it? | Verdict |
|---|---|---|---|---|
| `~/Carbon` (visible) | Zotero (`~/Zotero`), Superwhisper (`~/superwhisper`, moved there from `~/Documents`), Logseq (`~/logseq/graphs`), Postman (`~/Postman/files`), calibre (`~/Calibre Library`, shown in its welcome wizard), Standard Notes' old backups (`~/Standard Notes Backups`) | **Silent.** No Apple document I found allows or forbids a new top-level folder in the home folder. | Yes, by plain traversal. | **Tolerated, with real precedent among cross-platform library apps. It is not what Apple's own or Mac-only apps do** **(inference)**. |
| `~/.carbon` (hidden) | Developer and CLI tools: `~/.claude`, `~/.cursor`, `~/.ollama`, `~/.lmstudio`, `~/.vscode` | Apple says dot folders are hidden and hold things "the user should never have to use". | Only when named directly. ripgrep skips hidden folders while it walks a tree. | **Worse for Carbon.** It hides the very files ADR-0002 wants seen, and dot folders in `~` draw the most complaints. |
| `~/.local/share/carbon` or `~/.config/carbon` (XDG) | Joplin (`~/.config/joplin-desktop`), Karabiner-Elements, Zed (config only), Ghostty (as one option) | Not Apple's convention. Go, Electron and Rust's `dirs` all map these to `~/Library/Application Support` on macOS. | Hidden, like `~/.carbon`. | **Unusual for a consumer Mac app.** Joplin's own users complain about it. |
| `~/Documents/Carbon` (today) | Standard Notes (`~/Documents/<workspace>/Text Backups`), Zettlr (`~/Documents/Zettlr Tutorial`), older Superwhisper | "Apps must not write files to [Documents …] unless explicitly directed to do so by the user." | Yes, unless iCloud "Optimize Mac Storage" has evicted old files **(inference)**. | Kept only for comparison. |

**Recommendation: default to `~/Carbon`, visible, created silently on first use, and keep the existing setting that lets the person move it.**

- It is the only option that is visible to the person and to an agent, and not on Apple's protected list.
- Apple is silent about it, so it breaks no rule.
- Zotero chose the same default on purpose, to keep its data out of a Documents folder that may be synced to the cloud. Superwhisper, a direct competitor in dictation, moved its folder from `~/Documents/superwhisper` to `~/superwhisper` for the same reason.
- `~/.carbon` gives up the goal of ADR-0002 (a visible folder) and gains nothing in return. The home root is not protected whether the name starts with a dot or not **(inference)**.
- Before shipping, test the one claim no source settles: that a fresh Developer ID build reading `~/Carbon` gets no prompt (**unverified**, see Open questions).

## 1. Where comparable apps store user data by default

### Meeting and dictation apps

| App | Default user-data location on macOS | Visible / dot / hidden in `~/Library` | Asks the person? | Source |
|---|---|---|---|---|
| Granola | Cloud. A local cache is reported in `~/Library/Application Support/Granola` | Hidden in `~/Library` | No | **Unverified.** No Granola document gives a path. Its help says only that iPhone notes "sync to the Granola desktop app" ([Granola help](https://docs.granola.ai/help-center/ios/syncing-with-desktop)). |
| Otter | Cloud | — | No | **Unverified.** Otter's help center blocked automated reads, and I found no Otter page that gives a local path. |
| Fireflies (desktop) | Cloud. "Take Notes" mode "does not save a separate audio or video file" | — | No | [Fireflies guide](https://guide.fireflies.ai/articles/9115463123-does-the-desktop-app-save-an-audio-recording) |
| Krisp | Cloud: "all your recordings across all your apps will be stored in one centralized place in your Krisp account" | — | No | [Krisp release note](https://krisp.launchnotes.io/announcements/ann_SxWqbtgumoP7y) |
| Jamie | Cloud: "100% EU data storage and processing" | — | No | [Jamie](https://www.meetjamie.ai/lp-privacy-first). The local path is **unverified**. |
| tl;dv | Cloud: "All recordings are saved to your tl;dv library" | — | No | [tl;dv help](https://intercom.help/tldv/en/articles/14433337-bot-free-recording) |
| Notion AI meeting notes | A Notion page in the cloud. "A temporary copy of audio is stored locally on your device during the session" | — | No | [Notion help](https://www.notion.com/help/ai-meeting-notes) |
| MacWhisper | `~/Library/Application Support/MacWhisper` | Hidden in `~/Library` | No | [MacWhisper docs](https://docs.macwhisper.com/article/54-file-locations) |
| **Superwhisper** | **`~/superwhisper`** (history, modes, vocabulary). Recordings go in `~/superwhisper/recordings`. "Older installs may still use `~/Documents/superwhisper`" | **Visible, at the home root** | No. "Change folder" in Advanced settings | [Advanced settings](https://superwhisper.com/docs/get-started/settings-advanced#app-folder-location), [full docs](https://superwhisper.com/docs/llms-full.txt) |
| Hyprnote / Anarlog | `~/Library/Application Support/anarlog`. It moved there from a custom location in 1.4.26 | Hidden in `~/Library` | No | [macos-library-location.md §5](macos-library-location.md#5-what-comparable-apps-do) |
| Meetily | Recordings in **`~/Movies/meetily-recordings`**. The database is in the Tauri app data folder | Visible, inside a standard home subfolder | No | [recording_preferences.rs#L57-L69](https://github.com/Zackriya-Solutions/meeting-minutes/blob/a2cb62e827da7ef59f65064c97233efb2313878e/frontend/src-tauri/src/audio/recording_preferences.rs#L57-L69), [database/commands.rs#L88-L93](https://github.com/Zackriya-Solutions/meeting-minutes/blob/a2cb62e827da7ef59f65064c97233efb2313878e/frontend/src-tauri/src/database/commands.rs#L88-L93) |

Why Superwhisper moved matters most here. Its troubleshooting docs say: "iCloud Documents syncing can move a folder in Documents and cause this [failure to save modes] … Older installs kept the Superwhisper folder in `~/Documents`. The current default is `~/superwhisper` in your home directory" ([full docs](https://superwhisper.com/docs/llms-full.txt), "Unable to create mode"). A 2023 user request complained that the recordings folder "appeared on the first level of [the] iCloud Documents folder". The team called it "a great idea", and the request is now marked Completed ([feedback board](https://feedback.superwhisper.com/board/p/allow-to-customize-historyrecordings-folder)).

Meetily's `~/Movies` is a third route with no prompt: Apple's protected list names Desktop, Documents and Downloads, not Movies ([macos-library-location.md §1](macos-library-location.md#1-which-locations-are-tcc-protected-for-a-non-sandboxed-app)). But the same Apple rule that covers Documents also covers Movies ("Apps must not write files to the preceding directories unless explicitly directed"), and Markdown transcripts are not movies. I don't recommend it **(inference)**.

### Notes and knowledge apps

| App | Default location on macOS | Visible / dot / hidden in `~/Library` | Asks the person? | Source |
|---|---|---|---|---|
| Obsidian | None. The person picks the vault folder | Visible, wherever they choose | Yes | [Manage vaults](https://obsidian.md/help/manage-vaults) |
| Logseq | `~/logseq/graphs` for DB graphs. `~/.logseq` holds plugins and settings | Visible at the home root, plus a dot folder | No for DB graphs | [macos-library-location.md §5](macos-library-location.md#5-what-comparable-apps-do), [logseq#3462](https://github.com/logseq/logseq/issues/3462) |
| Zettlr | No default workspace (`openWorkspaces: []`). On first start it copies a tutorial into **`~/Documents/Zettlr Tutorial`** without asking | Visible, in Documents | No for the tutorial | [app-service-container.ts#L207-L211](https://github.com/Zettlr/Zettlr/blob/ecb71641be41e51a1fa013c180f1a04dd964f688/source/app/app-service-container.ts#L207-L211), [tutorial-open.ts#L34](https://github.com/Zettlr/Zettlr/blob/ecb71641be41e51a1fa013c180f1a04dd964f688/source/app/service-providers/commands/tutorial-open.ts#L34) |
| Joplin | `~/.config/joplin-desktop`, on **every** OS including macOS. The notes database and attachments live there | Dot folder (XDG style) | No | [determineBaseAppDirs.ts#L15-L19](https://github.com/laurent22/joplin/blob/b48e75856d81152c32e71f21075e1c043d9ea922/packages/lib/determineBaseAppDirs.ts#L15-L19) |
| Standard Notes | Notes are cloud and local storage. Text backups are switched on automatically and go to `~/Documents/<workspace>/Text Backups`. The old default was **`~/Standard Notes Backups`** at the home root | Visible, in Documents (old default: home root) | No | [FilesBackupService.ts#L163-L179](https://github.com/standardnotes/app/blob/695dad5d73f6607a56dd0ba4d78a290a7016ea67/packages/services/src/Domain/Backups/FilesBackupService.ts#L163-L179), [FileBackupsManager.ts#L101-L114](https://github.com/standardnotes/app/blob/695dad5d73f6607a56dd0ba4d78a290a7016ea67/packages/desktop/app/javascripts/Main/FileBackups/FileBackupsManager.ts#L101-L114) |

### Library apps and developer or CLI tools with a home-root folder

| App | Default | Visible or dot | Asks? | Source |
|---|---|---|---|---|
| **Zotero** | **`~/Zotero`** (since Zotero 5.0, 2017) | Visible | No. Can be changed in Settings › Advanced | [dataDirectory.js#L40-L46](https://github.com/zotero/zotero/blob/212a7d6a585d1209bc4e698a904490205f139500/chrome/content/zotero/xpcom/dataDirectory.js#L40-L46), [Zotero data](https://www.zotero.org/support/zotero_data) |
| calibre | **`~/Calibre Library`**. The welcome wizard creates it, then shows it with a Change button | Visible | Yes, but the field is prefilled and the folder already exists | [wizard/\_\_init\_\_.py#L802-L824](https://github.com/kovidgoyal/calibre/blob/dda26ee1702ba4b8807d1b9826ae3c1e84fe0e68/src/calibre/gui2/wizard/__init__.py#L802-L824), [calibre FAQ](https://manual.calibre-ebook.com/faq.html) |
| Postman | **`~/Postman/files`** (working directory) | Visible | No | [Postman docs](https://learning.postman.com/docs/getting-started/installation/settings/working-directory/) |
| Claude Code | `~/.claude`, `~/.claude.json`. Can be moved with `CLAUDE_CONFIG_DIR` | Dot | No | [Claude Code settings](https://code.claude.com/docs/en/settings) |
| Cursor | `~/.cursor` (for example `~/.cursor/mcp.json`) | Dot | No | [Cursor MCP docs](https://cursor.com/docs/context/mcp) |
| Ollama (CLI and Mac app) | `~/.ollama/models`. Can be moved with `OLLAMA_MODELS` | Dot | No | [envconfig/config.go#L113-L124](https://github.com/ollama/ollama/blob/8861adaa77839c961d3c574232a8865d65a426b6/envconfig/config.go#L113-L124), [faq.mdx#L235-L241](https://github.com/ollama/ollama/blob/8861adaa77839c961d3c574232a8865d65a426b6/docs/faq.mdx#L235-L241) |
| LM Studio | `~/.lmstudio/models`, with the CLI in `~/.lmstudio/bin` | Dot | No. The models folder can be changed in My Models | [LM Studio docs](https://lmstudio.ai/docs/app/advanced/import-model), [lms blog](https://www.lmstudio.ai/blog/lms) |
| VS Code | `~/.vscode/extensions`. Can be moved with `--extensions-dir` | Dot | No | [VS Code docs](https://code.visualstudio.com/docs/configure/extensions/extension-marketplace) |
| `~/Sites` | An Apple standard folder: "web pages used by the user's personal site (Web Sharing must be enabled …)" | Visible | — | [File System Programming Guide](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html). Apple created it. Whether current macOS still creates it is **unverified**. |
| Dropbox | Was `~/Dropbox`. On File Provider: "Your Dropbox folder will be moved to ~/Library/CloudStorage" | Was visible, now under `~/Library` (shown in the sidebar) | — | [Dropbox help](https://help.dropbox.com/installs/macos-support-for-expected-changes) |

Patterns **(inference)**:

- **A visible folder at the home root** is used by cross-platform apps whose data is a library the person owns: Zotero, calibre, Logseq, Postman, Superwhisper. Most are not Mac-only.
- **A dot folder at the home root** is used almost only by developer and CLI tools, whose users live in a terminal. None of the consumer note or meeting apps I checked uses one, except Joplin through `~/.config`.
- **Mac-only consumer apps** (Bear, Day One, MacWhisper, iA Writer, Apple Notes, see the earlier note) use `~/Library` or iCloud, never the home root.
- The closest match to Carbon, a local recorder whose output an agent reads, is Superwhisper, and it went from Documents to `~/superwhisper`.

## 2. What Apple says about top-level folders in the home folder

- **File System Programming Guide: silent on new top-level folders.** It lists the standard home subfolders and forbids writing into *them* unless the person directs it ("Apps must not write files to the preceding directories unless explicitly directed to do so by the user. The sole exception to this rule is the Library directory"). It never mentions creating a new sibling folder ([FSPG, File System Basics](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html), archived). So `~/Carbon` is neither allowed nor forbidden **(inference)**.
- **Apple argues against a hidden library.** In `~/Library`: "the Finder hides the Library directory … Therefore, you should never store files in this directory that you want the user to access." In Application Support: "The files should be app-specific but should never store user data" ([Mac App Programming Guide, The Mac Application Environment](https://developer.apple.com/library/archive/documentation/General/Conceptual/MOSXAppProgrammingGuide/AppRuntime/AppRuntime.html), archived). The newer FSPG wording is softer ("all app data files except those associated with the user's documents"). Both rule out putting Transcripts that the person reads in a hidden place.
- **Dot folders are for things the person never touches.** "Finder … hide[s] many files and directories that the user should never have to use … Any file or directory whose name starts with a period (.) character is hidden automatically. This convention is taken from UNIX" ([FSPG, Hidden Files and Directories](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html)). That is the opposite of a Library the person opens and copies paths from **(inference)**.
- **HIG: silent.** It sets no default location for an app's data ([HIG, File management](https://developer.apple.com/design/human-interface-guidelines/file-management); details in the earlier note).
- **Mac App Store: closes the door, but only through the sandbox.** Guideline 2.4.5(i): Mac App Store apps "must be appropriately sandboxed, and follow macOS File System Documentation" ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)). For a sandboxed app the home folder *is* its container ([Mac App Programming Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/MOSXAppProgrammingGuide/AppRuntime/AppRuntime.html)). Reaching the real `~/Carbon` would need `com.apple.security.temporary-exception.files.home-relative-path.read-write`, a temporary exception that must be justified in App Store Connect ([Temporary exception entitlements](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html)). This does not bind a Developer ID app, but `~/Carbon` would make a later App Store version harder **(inference)**.

Overall Apple is **neutral to silent** on `~/Carbon`. It **discourages** hidden places, both `~/Library` and dot folders, for files the person is meant to use.

## 3. XDG folders (`~/.config`, `~/.local/share`) on macOS

- **The XDG spec** sets `$XDG_DATA_HOME` to "`$HOME/.local/share`" and `$XDG_CONFIG_HOME` to "`$HOME/.config`" when they are not set ([XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/latest/)). It is a freedesktop.org (Linux desktop) spec, not an Apple one.
- **Standard libraries map them to `~/Library` on macOS:**
  - Go's `os.UserConfigDir`: "On Unix systems, it returns $XDG_CONFIG_HOME … else $HOME/.config. On Darwin, it returns $HOME/Library/Application Support" ([pkg.go.dev/os](https://pkg.go.dev/os#UserConfigDir)).
  - Electron's `appData`: "`$XDG_CONFIG_HOME` or `~/.config` on Linux, `~/Library/Application Support` on macOS" ([Electron app API](https://www.electronjs.org/docs/latest/api/app#appgetpathname)).
  - Rust's `dirs::data_dir`: `$HOME/.local/share` on Linux, `$HOME/Library/Application Support` on macOS ([docs.rs](https://docs.rs/dirs/latest/dirs/fn.data_dir.html)).
- **Who uses `~/.config` on macOS anyway:**
  - Command-line tools: `gh` defaults to `$HOME/.config/gh` ([gh environment](https://cli.github.com/manual/gh_help_environment)).
  - A few GUI apps aimed at developers or power users: Karabiner-Elements (`~/.config/karabiner/karabiner.json`, [docs](https://karabiner-elements.pqrs.org/docs/json/location/)), Zed for settings (`~/.config/zed/settings.json`, [docs](https://zed.dev/docs/configuring-zed)), and Joplin.
  - Ghostty reads `$HOME/.config/ghostty` and also a "macOS-specific path … `$HOME/Library/Application Support/com.mitchellh.ghostty`" ([Ghostty config](https://ghostty.org/docs/config)).
  - Zed keeps its *data* (extensions) in "`~/Library/Application Support/Zed`" on macOS but `~/.local/share/zed` on Linux ([Zed docs](https://zed.dev/docs/configuring-zed)). So even an XDG-friendly app does not use `~/.local/share` on macOS.
- **Joplin's own users push back.** "`~/.config` on macOS … is used to store all of Joplin's desktop profile data — not just configuration, but also its cache and resource attachments … 6.0G ./resources" ([joplin#16699](https://github.com/laurent22/joplin/issues/16699), 2026-09-29).

Verdict: `~/.config` is a niche habit of developer tools on macOS. **I found no consumer Mac app that keeps user data in `~/.local/share`** (**unverified** that none exists). It is hidden, so it fails ADR-0002 for the same reason `~/.carbon` does.

## 4. Complaints about apps cluttering `~`

Every complaint I found is about **dot folders and app data**, not about a visible user-data folder:

- **Ollama.** "[P]lease don't clutter the user home directory … the user home directory should be under the *user's* control, and applications may only write into it if explicitly instructed to do so by the user. Settings etc. belong in OS-specific locations; in particular, under `~/Library` on macOS" ([ollama#228](https://github.com/ollama/ollama/issues/228), 2023, 165 👍, still open). A second issue asks Ollama to "Adhere to the MacOS File System Programming Guide" and to move to `~/Library/Application Support/Ollama` ([ollama#584](https://github.com/ollama/ollama/issues/584)).
- **Claude Code.** "Claude Code does not respect the XDG Base Directory specification … creates ~/.claude.json and ~/.claude directory" ([claude-code#1455](https://github.com/anthropics/claude-code/issues/1455), 444 👍, still open, filed from Linux).
- **VS Code.** "Revisit VS Code folder structure for app data, settings, extensions" ([vscode#3884](https://github.com/microsoft/vscode/issues/3884), 2016, 709 👍, 224 comments, still open).
- **Logseq.** Asks to move `~/.logseq` to `~/.config/logseq` ([logseq#3462](https://github.com/logseq/logseq/issues/3462), 79 👍).
- **Joplin.** Gigabytes of attachments inside `~/.config` ([joplin#16699](https://github.com/laurent22/joplin/issues/16699)).

On the other side:

- **Zotero went *to* the home root on purpose.** In 2014 its lead developer first proposed Documents, because then a person could "open Documents and make a copy of that clearly named folder (On OS X, Spotlight doesn't even search in Application Support by default anyway …)" ([zotero#551 comment](https://github.com/zotero/zotero/issues/551#issuecomment-57949989)). A contributor then pointed out that Documents is often synced by OneDrive or Dropbox, and suggested "the user profile root … in line with the behavior of Dropbox/Google Drive/etc." ([zotero#552 comments](https://github.com/zotero/zotero/issues/552#issuecomment-62903659), [next](https://github.com/zotero/zotero/issues/552#issuecomment-62929285)). The change closed in 2016. Staff later advised: "it's better not to store the Zotero data directory in the Documents folder, which might be synced to the cloud (now or in the future), resulting in database corruption. Zotero 5.0 will use a "Zotero" directory at the root of your home directory" ([Zotero forums, 2017](https://forums.zotero.org/discussion/comment/268585/)).
- I found **no** issue in Zotero's, Superwhisper's or Logseq's trackers complaining that `~/Zotero`, `~/superwhisper` or `~/logseq` clutters the home folder. Absence of evidence is weak; I searched GitHub issues and the vendors' boards, not every forum (**unverified**).

So the backlash targets hidden, app-managed state in `~`. A visible folder holding the person's own files has not drawn the same reaction **(inference)**.

## 5. Challenging the premise

- **Is the Documents prompt even a problem for real users?** The earlier note found that "User consent is not required for an app to create new documents in any of these protected locations", and that files the app created are exempt. The prompt Carbon saw came from a *fresh code identity* reading files an earlier identity wrote. On a new machine with a shipped Developer ID build, Carbon creates `~/Documents/Carbon` itself, so the prompt may never appear (**unverified**, **(inference)**). The prompt would still appear when:
  - another Mac running Carbon has already written files that iCloud Desktop & Documents syncs in, or
  - the folder is restored from a backup, or
  - the signing identity changes.
  
  Even if the prompt is rare, Apple's rule against writing into Documents without the person's direction still stands.
- **Documents has a second cost besides TCC.** With "Desktop & Documents Folders" turned on, "your Desktop and Documents folders are moved into iCloud Drive" ([Apple, Store files in iCloud Drive](https://support.apple.com/guide/mac-help/store-files-in-desktop-documents-icloud-drive-mchle5a61431/mac)). "Optimize storage" keeps "only recently opened files on your Mac when space is needed" ([Apple, Optimize storage space](https://support.apple.com/guide/mac-help/optimize-storage-space-sysp4ee93ca4/mac)). An agent grepping a year of Transcripts could then hit files that are only in iCloud **(inference)**. This is the reason Zotero and Superwhisper gave for leaving Documents.
- **Is a dot folder at least "cleaner"?** It is hidden in Finder and in Open panels (FSPG above). ripgrep, which many agents use to search, skips "Hidden files and directories" during "automatic filtering" unless given `--hidden`. A hidden path named directly is still searched: "`rg foo .file` will search `.file` even though it is hidden" ([ripgrep GUIDE.md#L174-L198](https://github.com/BurntSushi/ripgrep/blob/91f5d22ef48bde459d90a8c7dbeab416e97d0f2b/GUIDE.md#L174-L198), [#L744-L747](https://github.com/BurntSushi/ripgrep/blob/91f5d22ef48bde459d90a8c7dbeab416e97d0f2b/GUIDE.md#L744-L747)). So `~/.carbon` works when Carbon hands the agent an exact path, but an agent searching `~` would miss it. A person browsing in Finder cannot see it without ⌘⇧. **(inference)**. It also falls in the category of folder that draws the complaints in §4.
- **Costs of `~/Carbon` that remain:**
  - It adds a folder to a place Apple keeps for its own standard folders.
  - The home folder is not in the default Finder sidebar, so the person may not find `~/Carbon` without a "Show in Finder" action (**unverified** for current macOS defaults).
  - It would need a temporary-exception entitlement if Carbon ever ships in the Mac App Store (§2).

## Verdict

- **`~/Carbon` is tolerated, not conventional.** Apple is silent. Well-known cross-platform library apps do it (Zotero, calibre, Logseq, Postman), and so does the closest competitor that keeps local files (Superwhisper, which left Documents for it). Mac-only consumer apps don't. That is acceptable for an app whose selling point is a folder of files the person owns **(inference)**.
- **`~/.carbon` is worse.** Apple describes dot folders as things the person "should never have to use". Finder and Open panels hide them. ripgrep skips them when walking `~`. They draw the strongest home-folder complaints. It is a developer-tool convention, not a consumer one.
- **XDG paths are unusual on macOS** and hidden. Rejected for the same reasons.
- **Recommended default: `~/Carbon`.**
  - Create it silently on first use.
  - Keep `SettingsKey.libraryFolder` so the person can move it later.
  - Show its path in the app, for example with a "Show in Finder" action, so the person can find it.
  - Keep `meetings.json` in Application Support, as ADR-0002 already does.
  - Use the capitalized name, as `~/Zotero` and `~/Calibre Library` do. The lowercase `~/superwhisper` and `~/logseq` look like CLI folders **(inference)**.

## Open questions and things I could not verify

- **No prompt for `~/Carbon` is still untested.** Apple's lists and Eclectic Light's secondary tests point to none, but nobody has tested a custom home-root folder (see the earlier note). Check with a Developer ID build on a clean user account: create and enumerate `~/Carbon`, re-sign with a different identity, and enumerate again.
- **Existing installs.** People whose setting or default still points to `~/Documents/Carbon` would hit the Documents prompt if Carbon reads or moves that folder. Whether to migrate them, or keep their current path, is a product decision this note does not settle **(inference)**.
- **Granola's and Otter's local storage** have no first-party documentation.
- **Spotlight and hidden folders.** I found no current Apple document stating whether Spotlight indexes dot folders in `~`.
- **Whether macOS still creates `~/Sites`.**
