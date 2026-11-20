#!/bin/bash
# The live transcript scan's Rust line reader (rust/, UsageBarCLI/TranscriptLineRust.swift) against
# the substring readers it replaces. Runs the Rust unit tests, builds the core with the test-only
# panic probe (its own target dir, so the shipped build never carries it), then compiles the
# watcher with the core linked and compares the two readers member by member and state by state.
# Count assertions with `command grep -c '^PASS:'`.
#
# The source list is the chromegap suite's closure of the watcher (run-chromegap-tests.sh).
#
# Speed gate G1 (not part of the suite): CTXRUST_BENCH=<file listing transcripts, one per line>.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET=14.0
(cd rust && cargo test --quiet --locked --workspace)
(cd rust && cargo build --quiet --release --locked -p usagebar_ffi --features panic-probe \
  --target-dir target/ctxrust-probe)
lib=rust/target/ctxrust-probe/release
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -O -I rust/include -L "$lib" -D USAGEBAR_RUST_REQUIRED -o "$out" \
  tests/ctxrust/main.swift tests/ctxrust/dump.swift tests/ctxrust/bench.swift \
  UsageBarCLI/ChromePreflight.swift \
  UsageBarCLI/ChromeRun.swift \
  UsageBarCLI/ChromeRunStream.swift \
  UsageBarCLI/SwitchCommand.swift UsageBarCLI/CodexHandoff.swift UsageBarCLI/CodexHandoffCommand.swift \
  UsageBarCLI/TranscriptLineBytes.swift \
  UsageBarCLI/QuotaKnock.swift \
  UsageBarCLI/CapResume.swift \
  UsageBarCLI/CapResumeLog.swift \
  UsageBarCLI/NativeModelCommand.swift \
  UsageBarCLI/QuotaKnockLogic.swift \
  UsageBarCLI/SelfSwitchResume.swift \
  UsageBarCLI/TranscriptWatcherScan.swift UsageBarCLI/RestartLiveWork.swift \
  UsageBarCLI/TranscriptLineView.swift \
  UsageBarCLI/TranscriptLineRust.swift \
  UsageBarCLI/ModelMenu.swift \
  UsageBarCLI/MCPAccountOffer.swift \
  UsageBarCLI/MCPPickOffer.swift \
  UsageBarCLI/ModelCommand.swift \
  UsageBarCLI/ModelHook.swift \
  UsageBarCLI/PickRows.swift \
  UsageBarCLI/UsageBarPrompt.swift \
  UsageBar/Core/PromptHookInput.swift \
  UsageBarCLI/MCPPicker.swift \
  UsageBarCLI/PromptHookBackstop.swift \
  UsageBarCLI/SwitchHook.swift \
  UsageBarCLI/WorktreeMenu.swift \
  UsageBarCLI/SwitchMenu.swift \
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
  UsageBarCLI/HookKnock.swift \
  UsageBarCLI/HostHealthKnockLogic.swift \
  UsageBar/Core/HostHealthLogic.swift UsageBar/Core/HostHealthCPU.swift \
  UsageBar/Core/KeystrokeText.swift \
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
  UsageBarCLI/Snapshot.swift \
  UsageBar/Core/ClaudeStableExecutable.swift \
  UsageBarCLI/StatusReport.swift \
  UsageBar/Core/HeldOverReset.swift \
  UsageBarCLI/SupervisorRuntime.swift \
  UsageBarCLI/TaskListPin.swift \
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
  UsageBarCLI/WindowRepickWindow.swift \

if [ -n "${CTXRUST_BENCH:-}" ]; then
  "$out" bench "$CTXRUST_BENCH"
else
  "$out"
fi
