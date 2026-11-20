#!/bin/bash
# Compiles the CLI's worktree logic (UsageBarCLI/Worktree.swift) together with a small assertion
# harness and runs it. Worktree.swift depends only on Snapshot.swift and GitRepoRoot.swift (the repo
# identity it shares with the per-project launch profile), so no Xcode target is needed. The rest of
# the source list is what those two drag in: ReloadRequest.swift for `scannedPidCount`, which the
# teardown's process scan shares; ResumePrompt.swift for the child environment SupervisorRuntime
# assembles; SessionSwitch.swift for the documents that share PendingNotice's state-directory
# suffix list, and Reload.swift for the idle gate that switch borrows; and WorktreeActivity.swift
# for TranscriptWatcher.swift plus the files that one needs to compile, because the teardown's busy
# gate calls the supervisor's own quiet test rather than a copy of it.
# Exits non-zero on failure. Uses real git and a temp filesystem for the create/link scenarios
# (see the five groups in docs/specs/changes/worktree-launch/design.md).
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -o "$out" \
  tests/worktree/main.swift \
  tests/worktree/teardownchecks.swift \
  tests/worktree/teardownpurechecks.swift \
  tests/worktree/treechecks.swift \
  tests/worktree/killchecks.swift \
  tests/worktree/originschecks.swift \
  UsageBarCLI/Worktree.swift \
  UsageBarCLI/GitRepoRoot.swift \
  UsageBarCLI/WorktreeTeardown.swift \
  UsageBarCLI/WorktreeRemoveGit.swift \
  UsageBarCLI/WorktreeKill.swift \
  UsageBarCLI/WorktreeProcessScan.swift \
  UsageBar/Core/WorktreeOrigins.swift \
  UsageBarCLI/WorktreeTree.swift \
  UsageBarCLI/WorktreeActivity.swift \
  UsageBarCLI/TranscriptWatcher.swift UsageBarCLI/TranscriptWatcherScan.swift UsageBarCLI/RestartLiveWork.swift UsageBarCLI/TranscriptLineView.swift UsageBarCLI/TranscriptLineRust.swift UsageBarCLI/TranscriptLineBytes.swift UsageBarCLI/TranscriptLoginSignals.swift UsageBar/Core/LimitReset.swift UsageBarCLI/LimitResetSignals.swift UsageBarCLI/SessionQuiet.swift UsageBarCLI/TranscriptSignals.swift UsageBarCLI/NativeModelCommand.swift UsageBar/Core/LaunchAxisNames.swift \
  UsageBarCLI/TranscriptFork.swift UsageBarCLI/RequestTranscript.swift UsageBarCLI/TranscriptIdentity.swift \
  UsageBarCLI/UnmanagedLaunch.swift \
  UsageBarCLI/DriftMonitor.swift \
  UsageBarCLI/SafeguardDrift.swift \
  UsageBarCLI/KeyboardIdle.swift \
  UsageBarCLI/OpenTurn.swift \
  UsageBarCLI/SupervisorRuntime.swift UsageBar/Core/ClaudeStableExecutable.swift UsageBarCLI/TaskListPin.swift UsageBarCLI/RelaunchPlan.swift \
  UsageBarCLI/ResumePrompt.swift \
  UsageBarCLI/LaunchFlags.swift UsageBarCLI/LaunchDecision.swift \
  UsageBarCLI/WorktreeMenu.swift \
  UsageBarCLI/Snapshot.swift UsageBarCLI/CodexLaunchArgs.swift \
  UsageBarCLI/AccountPick.swift UsageBarCLI/AccountPick+Handoff.swift \
  UsageBarCLI/AccountBinding.swift UsageBarCLI/AccountReserveReader.swift UsageBar/Core/AccountReserve.swift \
  UsageBarCLI/ProviderExecutable.swift \
  UsageBarCLI/AccountComfort.swift \
  UsageBar/Core/SessionMonitoring.swift UsageBarCLI/ReloadRequest.swift \
  UsageBarCLI/PendingNotice.swift UsageBarCLI/SessionState.swift UsageBarCLI/CodexStartupScreenRecord.swift UsageBarCLI/UserNotice.swift UsageBarCLI/SessionTurnEnd.swift UsageBarCLI/QuotaKnockNotice.swift UsageBarCLI/AgentRoster.swift \
  UsageBarCLI/SessionContext.swift UsageBar/Core/SessionPinScope.swift UsageBarCLI/MoveField.swift UsageBarCLI/Quarantine.swift \
  UsageBarCLI/SessionSwitch.swift UsageBarCLI/SwitchBadges.swift UsageBarCLI/HandoffResume.swift UsageBarCLI/ManualMoveState.swift UsageBarCLI/SwitchDecision.swift UsageBarCLI/SwitchRequest.swift UsageBarCLI/SessionAddressing.swift UsageBarCLI/AccountHome.swift \
  UsageBarCLI/Reload.swift
"$out"
