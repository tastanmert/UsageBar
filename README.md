# UsageBar

UsageBar is a macOS menu bar app that shows the usage limits of your Claude and OpenAI Codex subscriptions. It lists every account on your Mac with its 5-hour, weekly and top-model windows, pools them into one budget per provider, and starts new Claude Code and Codex sessions on the account with the most quota left.

It is free, open source and native (Swift, SwiftUI and AppKit, with a Rust core for reading conversation transcripts). Usage is read through the official `claude` and `codex` command line tools, on your own paid subscriptions.

## What it does

- **Every account side by side.** Each Claude and Codex login gets a row with its 5-hour, weekly and top-model windows and the time each one resets. Click a reset label to switch between a countdown and the exact time.
- **Account pools and a forecast.** The accounts of one provider are pooled into a single meter with an estimate of how long the pool lasts at your recent pace. A usage advisor line says whether your pace calls for another account.
- **Menu bar mark.** One segment per provider (or per account, if you prefer), with the session window above the weekly window.
- **Smart launch.** `usagebar claude` and `usagebar codex` start a session on the account whose quota lasts best right now, weighing reset times as well as remaining percent. Each provider can be set to Smart, Manual (you pin an account) or Off.
- **Handoff.** When an account hits its cap mid-conversation, the same conversation resumes on the next best account.
- **Session board.** Every session started through UsageBar appears as a card with its account, model, context size and state (working, idle or blocked waiting for you). A red dot in the menu bar shows when a session is waiting on you.
- **Cost tab.** Token totals per project and provider, read from the CLIs' local transcripts, plus Claude spend at Anthropic list prices. Codex tokens are counted but not priced.
- **Reset credits.** Banked rate-limit resets are shown on the account, and using one always asks for confirmation first.
- **Early start.** Optionally opens a closed 5-hour window with one short message, so the clock runs before you sit down.
- **Login health.** Accounts that are signed out or close to login expiry are flagged, with a shortcut to sign in again.

## Install

1. Download the latest `UsageBar-<version>.dmg` from [GitHub Releases](https://github.com/tastanmert/UsageBar/releases/latest).
2. Open the DMG and drag UsageBar into Applications.
3. Launch UsageBar. It lives in the menu bar and has no Dock icon. If macOS blocks the first launch, open System Settings > Privacy & Security and choose Open Anyway.

Requires macOS 14 or later, Apple Silicon or Intel.

### Updates

UsageBar checks for new versions on its own and installs them in the background. You can turn that off, or check by hand, in Settings > About. You never need to download a DMG again after the first install.

## First run

UsageBar needs Claude Code and/or the Codex CLI. If neither is installed, the first-run window offers to install one and walks you through signing in.

Accounts come from two places:

- **Existing logins.** UsageBar looks for Claude Code config folders matching `~/.claude*` and for Codex installs under `~/.codex*`, and shows each login it finds.
- **Add an account.** In Settings > Accounts, choose Add an account. UsageBar creates the next numbered config folder (for example `~/.claude2`) and opens the provider's own sign-in page in your browser. You can have the new account link to your main account's instructions, skills, hooks, agents, settings and conversation history. Sign-in details are never shared. From a terminal, `usagebar add claude` or `usagebar add codex` does the same.

## Integrations

Settings > Integrations installs each piece with one click and removes it cleanly. Install all covers every row except Shared harness.

| Row | What it installs |
| --- | --- |
| Command line tool | Links the bundled `usagebar` command into `/usr/local/bin`. macOS asks for your password if that folder needs it. |
| Shared harness | Points your other accounts at the main account's setup. Conversations, inboxes and memory notes merge into the main account, and nothing is deleted. Not part of Install all. |
| Claude shell integration | A small shim so a bare `claude` follows your launch policy. |
| Codex shell integration | The same for a bare `codex`. |
| Claude status line | Shows the active account, model and effort under each Claude Code session, and optionally the quota bars. An existing custom status line keeps running and is restored on removal. |
| Claude session board | A Notification hook that lets the board show which sessions are working or waiting. |
| Codex session status | Codex hooks for working and idle states. Review them in Codex `/hooks`. |
| Claude subagent count | Hooks that add each session's working subagent count to its card. |
| Claude quota warning | Hooks that tell a session when its account is running low. |
| Claude Code skill | A skill that teaches Claude Code to answer quota questions, plus the `/usagebar` command and an MCP server for account and model pickers. |

Hook rows leave whatever you already registered on the same event in place, and removal takes out only UsageBar's own entries.

## Command line

The `usagebar` command reads a local snapshot written by the app, so any number of terminals cost no extra usage reads.

```sh
usagebar status               # accounts, windows, resets
usagebar status --json        # the same, machine readable
usagebar claude               # start Claude Code on the best account
usagebar claude -w feature    # start in a git worktree named feature
usagebar codex                # start Codex on the best account
usagebar resume               # move this directory's latest conversation to another account
usagebar account <name>       # move the current session to another account
usagebar model <model>        # pin the current conversation to a model
usagebar add claude           # sign in one more account
usagebar cost                 # token and spend totals (add --json)
usagebar reload               # restart supervised sessions at their next quiet moment
usagebar session send "text" --session <pid>
usagebar update
usagebar help
```

Run `usagebar help` for the full list. Optional aliases:

```sh
alias c='usagebar claude'
alias cc='usagebar claude --continue'
```

## Build from source

You need Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and a Rust toolchain (`rustup` picks the version pinned in `rust/rust-toolchain.toml`).

```sh
brew install xcodegen
git clone https://github.com/tastanmert/usagebar && cd usagebar
xcodegen generate
xcodebuild -project UsageBar.xcodeproj -scheme UsageBar -configuration Release -destination 'platform=macOS' build
```

To package a DMG, run `scripts/make-release.sh --unsigned` for a local test build, or `scripts/make-release.sh` for a signed and notarized one. The one-time setup is in [docs/releasing.md](docs/releasing.md).

`project.yml` is the source of truth for the Xcode project. `UsageBar.xcodeproj` is generated and is not edited by hand. The Rust core is built by `scripts/build-rust-core.sh` as part of the build.

## Privacy

- Usage is read by running the official `claude` and `codex` CLIs. UsageBar does not proxy, share or resell access, and it does not log or send tokens.
- Reading a Claude login's expiry date means opening the local credential store briefly to extract the date. Only the date is kept.
- After a sign-in that UsageBar drove, it marks Claude Code's first-run wizard as completed in that one config folder. It merges one key and never replaces the file.
- The Cost tab reads the CLIs' local transcripts on your Mac. They never leave it.
- UsageBar has no telemetry: no usage ping, no analytics and no crash reporting.
- The network requests are the ones the official CLIs make to read usage, plus requests to `api.anthropic.com` that list and claim Claude reset credits, which run only for those features.
- Plan renewal dates are read a few times a day with one GET per account. For Codex, UsageBar asks the official CLI for its access token, keeps it in memory for one request to `chatgpt.com/backend-api/subscriptions` and drops it. `auth.json` is never opened.
- For Claude, the renewal date is only on claude.ai. It is read after you sign in to claude.ai inside UsageBar, in a web session kept apart from your browser and from every other account. Without that sign-in nothing is sent.
- Local state lives in `~/.usagebar`, including the snapshot at `~/.usagebar/snapshot.json`, which holds percentages and paths and no tokens.

## Documentation

- [Claude to Codex harness](docs/harness.md)
- [Session wait events](docs/session-wait-events.md)

## License

MIT. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
