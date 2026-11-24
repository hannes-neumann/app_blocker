# FocusFlow

**A macOS menu bar app for deep work:** a Pomodoro timer that blocks distracting apps and websites, turns quick
notes into estimated todos with a local language model, tracks time per project automatically, and lets Claude
plan your todos into your calendar.

Everything runs on your Mac. No account, no screen recording, and no collection of screen pixels.
Tracking does not store the text it reads: it uses macOS Accessibility text only to match project names and
automatically assign activity.

Pseudonymous telemetry uses a random, resettable identifier; it is opt-in and off by default. When enabled,
events are sent to PostHog's EU free tier.
See [PRIVACY.md](PRIVACY.md).

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

## Install

Needs macOS 14 (Sonoma) or later, on Apple silicon or Intel.

1. Download the DMG from the [latest release](https://github.com/hannes-neumann/app_blocker/releases/latest) and drag
   FocusFlow into **Applications**. Start it from there, not from the DMG, or updates cannot be installed.
2. Open it. macOS says it cannot verify the app: click **Done**, then System Settings → Privacy & Security →
   **Open Anyway**. Once only. FocusFlow is not notarized, because that needs Apple's paid developer program.
3. FocusFlow lives in the menu bar. It asks once whether it may send pseudonymous usage data; “No” changes nothing
   about how it works ([PRIVACY.md](PRIVACY.md)).

| macOS asks for | Why | Needed? |
| --- | --- | --- |
| Admin password, once | helper that blocks websites through `/etc/hosts` | only for website blocking |
| Accessibility | window titles and visible text for time tracking | only for time tracking |
| Control of your browser | address of the active tab | only if turned on in time tracking |

**Updates** arrive inside the app (Settings → General → Updates), never during a focus session, and are checked with an
EdDSA signature. **Problems?** [Open an issue](https://github.com/hannes-neumann/app_blocker/issues/new/choose), without
personal logs. **Uninstall:** remove the helper under Settings → Blocking, quit, delete the app and
`~/Library/Application Support/FocusFlow`.

| System | Works? |
| --- | --- |
| macOS 26 or later | yes, AI with Apple Intelligence (where available) or Ollama |
| macOS 14 and 15 | yes, AI with Ollama; without it, keyword estimates |
| macOS 13 or earlier | no |
| Windows, Linux | no |

To build it yourself: Swift 6 from the Xcode Command Line Tools; full Xcode is not needed.

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

## Sharing with friends

Friends only need the release link above. To get there, once:

1. Create a PostHog project (EU region, “Discard client IP data” on).
2. Create the GitHub environment `release` with yourself as reviewer, for tags `v*` only.
3. Run `swift build`, then `scripts/setup-release.sh`: it creates the signing certificate and the update key and stores
   them as secrets. **Back both up.** Without them, existing users may not be able to update.
4. Fill in contact and retention in `PRIVACY.md`; the release stops while it contains a TODO.
5. Try it: Actions → Release → Run workflow builds everything without publishing. Install that DMG on a second Mac.

For every version, add a `## X.Y.Z` section to `CHANGELOG.md`, raise the version in `Resources/Info.plist`, then on `main`:

```bash
git tag -a v0.1.0 -m "FocusFlow 0.1.0" && git push origin v0.1.0
```

Approve the run on GitHub; it signs, uploads and publishes, and installed apps find the update. Before the first
friend gets the app, publish two versions and update from one to the other on your own Mac.

A DMG from a plain local `scripts/release.sh` works too, but has no update or PostHog key: it never updates itself.
Details, rollback and lost keys: [docs/RELEASING.md](docs/RELEASING.md).

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
| Local event log | `Analytics.swift` (JSON lines, size-capped; optional pseudonymous telemetry is opt-in) |
| Translations | `Localization.swift` |
| MCP server | `Sources/FocusFlowMCP/main.swift` |

Data lives in `~/Library/Application Support/FocusFlow/`. GitHub Releases and Actions are free for this
public repository. Builds are not notarized without a paid Apple Developer account; Apple's fee waiver
does not cover individuals. On first launch choose **Open Anyway** under System Settings → Privacy &
Security. Later Sparkle updates are verified with EdDSA signatures.

## Known limitations

- Tabs of a blocked site that are already open may keep working until reloaded, because browsers cache connections.
- The shortcuts are fixed to `⌃⌥N` and `⌃⌥T`.
- Apps with unsaved documents ask before quitting; if you decline, FocusFlow only hides them.

## License

[MIT](LICENSE)
