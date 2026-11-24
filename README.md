# FocusFlow

**A macOS menu bar app for deep work:** a Pomodoro timer that blocks distracting apps and websites, turns quick
notes into estimated todos with a local language model, tracks time per project automatically, and lets Claude
plan your todos into your calendar.

Everything runs on your Mac. No account, no cloud, no screen recording, and no collection of screen pixels.
Tracking does not store the text it reads: it uses macOS Accessibility text only to match project names and
automatically assign activity.

> Deutsche Dokumentation mit allen Details: [docs/README.de.md](docs/README.de.md)

## Features

- **Focus timer in the menu bar**: focus sessions, short and long breaks, rounds; pause, skip or stop.
- **Exclusion lists**: choose apps and websites to exclude while in focus. Project and task app lists can override
  the global app list. Website domains are blocked system-wide via `/etc/hosts` through a small helper.
- **Admin-password protected website blocking**: installing the helper requires your macOS admin password once.
  It only adds the block while FocusFlow is running and in a focus session, and removes it when the app quits or
  crashes.
- **Keyboard first**: `⌃⌥N` opens a floating quick note anywhere; `⌃⌥T` starts a focus with your own duration and
  lets you pick a project or task with ↑↓ (or controls a running session).
- **Local AI for todos**: a note like "prepare slides for monday" becomes one or more concrete todos with a time
  estimate, using Apple Intelligence (macOS 26) or any [Ollama](https://ollama.com) model. Requests are batched
  shortly before your next break, and the model is unloaded right after, so it costs little power and memory.
- **Break suggestions**: each break suggests the longest open todo that still fits.
- **Projects and insights**: colors, icons, weekly goals, focus time per project, estimate accuracy, best hours of
  the day, and automatically worded observations. Projects can be marked as finished or reopened from the …
  menu on the project page. Finished projects keep their history and statistics and appear under “Finished
  projects” in the overview, but no longer in selection menus (timer, todos, assignments). Automatic tracking no
  longer assigns time to them, and Claude (MCP) no longer sees them. Open todos stay as they are.
- **Automatic time tracking** (opt-in, outside focus too): rules by app, domain or window title assign your time
  to projects outside focus sessions. During a focus session, the selected project receives the tracked time.
  Project names in visible Accessibility text can also infer a project, but only on a unique match; ambiguous text
  stays unassigned. It considers the window visible *next to* the front app, so a PDF beside a chat can count for
  the right project.
- **Text privacy**: no screen capture or pixel collection is used. Password fields (`AXSecureTextField`) are never
  read, and excluded apps are skipped entirely. By default this includes password managers and private messaging
  apps such as 1Password, Bitwarden, Keychain Access, WhatsApp, Signal, Telegram, Discord and Messages. You can
  edit the exclusion list. Read text is used only for project matching and is never saved.
- **Claude integration (MCP)**: a bundled MCP server lets Claude read your todos and focus history, plan them as
  focus blocks into free calendar slots, and add, complete or start todos.
- **German and English** throughout.

## Requirements

- macOS 14 or later (Apple silicon or Intel)
- To build: Swift 6 via the Xcode Command Line Tools; full Xcode is not needed
- Optional: Ollama (`brew install ollama`) for the AI features on macOS before 26

## Build and run

```bash
./scripts/build-app.sh
open build/FocusFlow.app
```

For day-to-day work there is a small command that builds and restarts the app from any directory:

```bash
ln -s "$PWD/scripts/focusflow" ~/.local/bin/focusflow
focusflow            # build and restart
focusflow status     # is the newest build running, and only once?
focusflow help       # build, start, stop, test, release
```

A running focus session is only ended with `--force`.

## Tests

```bash
./scripts/test.sh
```

Swift Testing covers duration parsing, note estimates, translations (every text in both languages with matching
placeholders), tracking rules, the AI batch queue, todo handling, loading older data files, and the MCP server run
as a separate process. Tests use a scratch data folder and never touch your real data. GitHub Actions runs them on
every push; `git config core.hooksPath .githooks` also runs them before each push locally.

## Sharing builds

`./scripts/release.sh` builds a universal app and packs a DMG and a ZIP in `build/release`, signed with a
self-signed certificate named `FocusFlow Developer` (see [docs/README.de.md](docs/README.de.md#weitergeben) for how
to create it). The app is not notarized, so on first launch it has to be allowed once under
System Settings → Privacy & Security → "Open Anyway"; the DMG includes short instructions.

## Claude (MCP)

The build places `focusflow-mcp` inside the app bundle. Settings → General → Claude copies a ready-made
configuration for Claude Desktop or Claude Code. Tools:

| Tool | What it does |
| --- | --- |
| `get_planning_context` | open todos with time to plan, projects and weekly goals, pomodoro settings, estimate factor, best focus hours |
| `list_todos` | todos, optionally by project or including finished ones |
| `plan_focus_blocks` | packs todos into free slots as pomodoro blocks with breaks; returns calendar titles, descriptions and a start link; creates nothing itself |
| `add_todo`, `complete_todo`, `start_focus` | change todos or start a session through the running app |

The server only reads the app's files. Changes go through `focusflow://` links to the running app and need a
token that only your user can read.

## How it is built

| Part | Where |
| --- | --- |
| Timer and state | `AppState.swift` |
| App and website blocking | `AppBlocker.swift`, `DomainBlocker.swift` |
| Global shortcuts | `HotKey.swift` (Carbon hot keys, no Accessibility permission needed) |
| Todos and suggestions | `TodoStore.swift` |
| AI | `AIEngine.swift`, `AIBatchQueue.swift`, `OllamaClient.swift`, `TodoRefiner.swift` |
| Time tracking | `ActivityTracker.swift`, `Views/TrackingViews.swift` |
| Insights and dashboard | `StatsStore.swift`, `Insights.swift`, `Views/` |
| Local event log | `Analytics.swift` (JSON lines, size-capped, never leaves the Mac) |
| Translations | `Localization.swift` |
| MCP server | `Sources/FocusFlowMCP/main.swift` |

Data lives in `~/Library/Application Support/FocusFlow/`.

## Known limitations

- Tabs of a blocked site that are already open may keep working until reloaded, because browsers cache connections.
- The shortcuts are fixed to `⌃⌥N` and `⌃⌥T`.
- Apps with unsaved documents ask before quitting; if you decline, FocusFlow only hides them.

## License

[MIT](LICENSE)
