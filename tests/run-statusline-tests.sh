#!/bin/bash
# Compiles the status line's own formats (UsageBarCLI/Statusline.swift) with a small assertion harness
# and runs it. No Xcode test target needed; exits non-zero on failure.
#
# Two harness files: main.swift is the row itself plus the surfaces that print what it used to
# (`usagebar status`, `usagebar help`), completionchecks.swift is what `usagebar completion zsh` offers at
# the cursor. Split for file size; both are surfaces presented to somebody typing.
#
# The source list is that file's transitive closure: the snapshot it reads, the account pick and
# comfort gate the snapshot types drag in, and the per-supervisor state the line renders (the drift
# badge, the pending notice, the session context, and the registry they all live in).
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -o "$out" tests/statusline/main.swift tests/statusline/completionchecks.swift \
  UsageBarCLI/Statusline.swift UsageBarCLI/Usage.swift UsageBarCLI/OverlayCLI.swift UsageBarCLI/Completion.swift UsageBarCLI/HarnessCompletion.swift UsageBarCLI/RepoCompletion.swift UsageBarCLI/CompletionData.swift UsageBarCLI/Snapshot.swift UsageBar/Core/ClaudeStableExecutable.swift UsageBarCLI/CodexLaunchArgs.swift UsageBarCLI/AccountPick.swift UsageBarCLI/AccountPick+Handoff.swift \
  UsageBarCLI/AccountBinding.swift UsageBarCLI/AccountReserveReader.swift UsageBar/Core/AccountReserve.swift \
  UsageBarCLI/AccountComfort.swift UsageBarCLI/SupervisorRuntime.swift UsageBarCLI/TaskListPin.swift UsageBarCLI/RelaunchPlan.swift UsageBar/Core/SessionMonitoring.swift UsageBarCLI/ReloadRequest.swift UsageBarCLI/LiveRates.swift \
  UsageBarCLI/DriftMonitor.swift UsageBarCLI/PendingNotice.swift UsageBarCLI/SessionState.swift UsageBarCLI/CodexStartupScreenRecord.swift UsageBarCLI/UserNotice.swift UsageBarCLI/SessionTurnEnd.swift UsageBarCLI/QuotaKnockNotice.swift UsageBarCLI/SessionContext.swift UsageBar/Core/SessionPinScope.swift UsageBarCLI/MoveField.swift UsageBarCLI/AgentRoster.swift \
  UsageBarCLI/SessionSwitch.swift UsageBarCLI/SwitchBadges.swift UsageBarCLI/HandoffResume.swift UsageBarCLI/ManualMoveState.swift UsageBarCLI/SwitchDecision.swift UsageBarCLI/SwitchRequest.swift UsageBarCLI/SessionAddressing.swift UsageBarCLI/AccountHome.swift UsageBarCLI/GitRepoRoot.swift UsageBarCLI/Reload.swift \
  UsageBarCLI/LaunchFlags.swift UsageBarCLI/LaunchDecision.swift UsageBarCLI/ProviderExecutable.swift UsageBarCLI/ResumePrompt.swift \
  UsageBarCLI/TranscriptWatcher.swift UsageBarCLI/TranscriptWatcherScan.swift UsageBarCLI/RestartLiveWork.swift UsageBarCLI/TranscriptLineView.swift UsageBarCLI/TranscriptLineRust.swift UsageBarCLI/TranscriptLineBytes.swift UsageBarCLI/TranscriptLoginSignals.swift UsageBar/Core/LimitReset.swift UsageBarCLI/LimitResetSignals.swift UsageBarCLI/SessionQuiet.swift UsageBarCLI/TranscriptSignals.swift UsageBarCLI/NativeModelCommand.swift UsageBar/Core/LaunchAxisNames.swift UsageBarCLI/TranscriptFork.swift UsageBarCLI/RequestTranscript.swift UsageBarCLI/TranscriptIdentity.swift UsageBarCLI/UnmanagedLaunch.swift UsageBarCLI/OpenTurn.swift \
  UsageBarCLI/KeyboardIdle.swift UsageBarCLI/Quarantine.swift UsageBarCLI/SafeguardDrift.swift
"$out"
