#!/bin/bash
# Compiles the Chrome-gap notice (UsageBarCLI/ChromeReach.swift, the branch in UsageBarCLI/HookKnock.swift)
# with its assertion harness and runs it. No Xcode target is needed;
# exits non-zero on failure. Every collaborator is injected, so nothing here touches a real ~/.usagebar,
# supervisor, snapshot, Claude session or browser.
#
# The source list is the closure of `runHookKnock` and the live defaults it names (the supervisor's
# account and child readers, the snapshot), found by compiling and adding each file a missing symbol
# lives in. It is about a third of the supervisor suite's list and compiles in about a third of the
# time. Count assertions with `command grep -c '^PASS:'`.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -o "$out" tests/chromegap/main.swift tests/chromegap/routingchecks.swift \
  tests/chromegap/preflightchecks.swift tests/chromegap/runnerchecks.swift UsageBarCLI/ChromePreflight.swift UsageBarCLI/ChromeRun.swift UsageBarCLI/ChromeRunStream.swift UsageBarCLI/SwitchCommand.swift UsageBarCLI/CodexHandoff.swift UsageBarCLI/CodexHandoffCommand.swift \
  UsageBarCLI/TranscriptLineBytes.swift \
  UsageBarCLI/QuotaKnock.swift \
  UsageBarCLI/CapResume.swift UsageBarCLI/CapResumeLog.swift UsageBarCLI/NativeModelCommand.swift UsageBarCLI/QuotaKnockLogic.swift \
  UsageBarCLI/SelfSwitchResume.swift UsageBarCLI/TranscriptWatcherScan.swift UsageBarCLI/RestartLiveWork.swift UsageBarCLI/TranscriptLineView.swift UsageBarCLI/TranscriptLineRust.swift \
  UsageBarCLI/ModelMenu.swift \
  UsageBarCLI/MCPAccountOffer.swift UsageBarCLI/MCPPickOffer.swift UsageBarCLI/ModelCommand.swift UsageBarCLI/ModelHook.swift UsageBarCLI/PickRows.swift UsageBarCLI/UsageBarPrompt.swift \
  UsageBar/Core/PromptHookInput.swift UsageBarCLI/MCPPicker.swift \
  UsageBarCLI/PromptHookBackstop.swift \
  UsageBarCLI/SwitchHook.swift UsageBarCLI/WorktreeMenu.swift \
  UsageBarCLI/SwitchMenu.swift \
   \
   \
   \
   \
   \
   \
   \
   \
  UsageBar/Core/AccountReserve.swift \
  UsageBar/Core/ChromeSettingSignal.swift \
  UsageBar/Core/LaunchAxisNames.swift \
  UsageBar/Core/LimitReset.swift \
  UsageBar/Core/PickContract.swift \
  UsageBar/Core/SessionMonitoring.swift \
  UsageBar/Core/SessionPinScope.swift \
  UsageBarCLI/AccountBinding.swift \
  UsageBarCLI/AccountComfort.swift \
  UsageBarCLI/AccountHome.swift \
  UsageBarCLI/AccountPick.swift UsageBarCLI/AccountPick+Handoff.swift \
  UsageBarCLI/AccountReserveReader.swift \
  UsageBarCLI/AgentRoster.swift \
  UsageBarCLI/ChromeReach.swift \
  UsageBarCLI/CodexLaunchArgs.swift \
  UsageBarCLI/CodexSessionEvents.swift \
  UsageBarCLI/CodexSessionInput.swift \
  UsageBarCLI/DriftMonitor.swift \
  UsageBarCLI/FollowAdoption.swift \
  UsageBarCLI/GitRepoRoot.swift \
  UsageBarCLI/HookKnock.swift UsageBarCLI/HostHealthKnockLogic.swift \
  UsageBar/Core/HostHealthLogic.swift UsageBar/Core/HostHealthCPU.swift UsageBar/Core/KeystrokeText.swift \
  UsageBarCLI/KeyboardIdle.swift \
  UsageBarCLI/LaunchFlags.swift UsageBarCLI/LaunchDecision.swift \
  UsageBarCLI/LimitResetSignals.swift \
  UsageBarCLI/ManualMoveState.swift \
  UsageBarCLI/MessagingSocket.swift \
  UsageBarCLI/ModelRequest.swift \
  UsageBarCLI/MoveField.swift \
  UsageBarCLI/OpenTurn.swift \
  UsageBarCLI/PendingNotice.swift \
  UsageBarCLI/ProjectPolicy.swift \
  UsageBarCLI/ProviderExecutable.swift \
  UsageBarCLI/ProviderReopen.swift \
  UsageBarCLI/LaunchDir.swift tests/shared/selfupdatebinary.swift \
  UsageBarCLI/Quarantine.swift \
  UsageBarCLI/QuotaKnockHookContract.swift \
  UsageBarCLI/QuotaKnockNotice.swift \
  UsageBarCLI/Rebalance.swift \
  UsageBarCLI/RelaunchPlan.swift \
  UsageBarCLI/Reload.swift \
  UsageBarCLI/ReloadRequest.swift \
  UsageBarCLI/RequestTranscript.swift \
  UsageBarCLI/ResumePrompt.swift \
  UsageBarCLI/SafeguardDrift.swift \
  UsageBarCLI/SessionAddressing.swift \
  UsageBarCLI/SessionAddressLookup.swift \
  UsageBarCLI/SessionClear.swift \
  UsageBarCLI/SessionContext.swift \
  UsageBarCLI/SessionInput.swift UsageBarCLI/AutomaticInput.swift \
  UsageBarCLI/SessionInputAutomatic.swift \
  UsageBarCLI/SessionInputCommand.swift \
  UsageBarCLI/CodexStartupChoice.swift UsageBarCLI/CodexStartupChoiceCommand.swift UsageBarCLI/CodexStartupScreen.swift \
  UsageBarCLI/SessionInputDraft.swift \
  UsageBarCLI/SessionInputLanding.swift \
  UsageBarCLI/SessionInputLog.swift \
  UsageBarCLI/SessionInputOccupant.swift \
  UsageBarCLI/SessionInputRequest.swift \
  UsageBarCLI/SessionInputTick.swift \
  UsageBar/Core/ProjectStatusLine.swift UsageBarCLI/SessionInventory.swift \
  UsageBarCLI/SessionModel.swift \
  UsageBarCLI/SessionProjectAddress.swift \
  UsageBarCLI/SessionQuiet.swift \
  UsageBarCLI/SessionSendVerb.swift \
  UsageBarCLI/SessionSendWait.swift \
  UsageBarCLI/SessionState.swift UsageBarCLI/CodexStartupScreenRecord.swift \
  UsageBarCLI/SessionSwitch.swift \
  UsageBarCLI/SessionTurnEnd.swift \
  UsageBarCLI/Snapshot.swift UsageBar/Core/ClaudeStableExecutable.swift \
  UsageBarCLI/StatusReport.swift UsageBar/Core/HeldOverReset.swift \
  UsageBarCLI/SupervisorRuntime.swift UsageBarCLI/TaskListPin.swift \
  UsageBarCLI/SwitchBadges.swift UsageBarCLI/HandoffResume.swift \
  UsageBarCLI/SwitchDecision.swift \
  UsageBarCLI/SwitchRequest.swift \
  UsageBarCLI/TranscriptFork.swift \
  UsageBarCLI/TranscriptIdentity.swift \
  UsageBarCLI/TranscriptLoginSignals.swift \
  UsageBarCLI/TranscriptSignals.swift \
  UsageBarCLI/TranscriptWatcher.swift \
  UsageBarCLI/UnmanagedLaunch.swift \
  UsageBarCLI/UsageAdvisor.swift \
  UsageBarCLI/UsageAdvisorMath.swift \
  UsageBarCLI/UserNotice.swift \
  UsageBarCLI/WindowRepick.swift \
  UsageBarCLI/WindowRepickWindow.swift
"$out"
