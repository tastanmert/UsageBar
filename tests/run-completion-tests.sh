#!/bin/bash
# Runs the completion script (UsageBarCLI/Completion.swift) inside a real interactive zsh and checks
# what it puts at the cursor. No Xcode test target needed; exits non-zero on failure.
#
# HERMETIC: the `usagebar` the script asks its questions of is a stub in this fixture, so the answers
# are the fixture's rather than this machine's fleet - the assertions can then name the worktrees
# and accounts they expect. What is under test is the script's half of the contract: given those
# lines on stdout, these words at the cursor.
set -euo pipefail
cd "$(dirname "$0")/.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The script itself, out of the constant the CLI prints it from.
swiftc UsageBar/Core/BrandPaths.swift -o "$work/dump" tests/completion/main.swift \
  UsageBarCLI/Completion.swift UsageBarCLI/OverlayCLI.swift UsageBarCLI/HarnessCompletion.swift UsageBarCLI/RepoCompletion.swift UsageBarCLI/CompletionData.swift UsageBarCLI/Snapshot.swift UsageBar/Core/ClaudeStableExecutable.swift UsageBarCLI/CodexLaunchArgs.swift UsageBarCLI/AccountPick.swift UsageBarCLI/AccountPick+Handoff.swift \
  UsageBarCLI/AccountBinding.swift UsageBarCLI/AccountReserveReader.swift UsageBar/Core/AccountReserve.swift \
  UsageBarCLI/AccountComfort.swift UsageBarCLI/ProviderExecutable.swift UsageBarCLI/ResumePrompt.swift \
  UsageBar/Core/LaunchAxisNames.swift
mkdir -p "$work/fpath" "$work/stub" "$work/repo"
"$work/dump" > "$work/fpath/_usagebar"

# A syntax error would fail every behaviour check below with the same unhelpful silence.
zsh -n "$work/fpath/_usagebar"

# The stub the completion asks. Same contract as the real binary: `worktree list` is one
# tab-separated line per worktree with the branch first, `completion data accounts` is one candidate
# per line. USAGEBAR_STUB_MODE=bare answers as a repository with no worktrees does (nothing on stdout,
# a note on stderr, exit 0).
cat > "$work/stub/usagebar" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "worktree list")
    if [ "${USAGEBAR_STUB_MODE:-full}" = bare ]; then
      echo "no worktrees" >&2
      exit 0
    fi
    printf 'wt-alpha\t2 days ago\t\t-\tsome commit subject\n'
    printf 'wt-beta\t3 weeks ago\t*\t2 agents\tanother subject\n'
    exit 0
    ;;
  "completion data")
    # One answer per provider, and they share no name: `usagebar project set --account` picks its
    # provider off the whole line, so a suite where both providers answered the same words could
    # not tell a right answer from a left-of-the-cursor guess.
    [ "$3" = accounts ] || exit 2
    case "$4" in
      claude) printf 'Stub One\nStub Two\n' ;;
      codex) printf 'Codex Only\n' ;;
      *) exit 2 ;;
    esac
    exit 0
    ;;
esac
exit 2
STUB
chmod +x "$work/stub/usagebar"

# A local file must appear only for explicit maintenance path options, never launch prompts.
touch "$work/repo/a-file-here.txt"

zsh -f tests/completion/drive.zsh "$work/fpath" "$work/stub" "$work/repo"
