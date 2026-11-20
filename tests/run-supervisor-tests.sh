#!/bin/bash
# Compiles the supervisor's transcript watcher (model tracking guards) with a small assertion
# harness and runs it. No Xcode test target needed; exits non-zero on failure.
#
# COUNTING THE ASSERTIONS: `command grep -c '^PASS:'`, anchored, and never a bare `grep PASS`. This
# harness prints to the terminal a supervised session is already using, so UsageBar's own runtime log
# lands in the same stream: a line like `PASS[usagebar] cap hit -> handing off to B` is not an
# assertion and an unanchored count adds it. The number in a commit message is only as good as the
# command that produced it, and a bare count is off by however many of those the run happened to
# catch (05cde88 published one such number, and the commit after it copied it).
#
# ProcessFootprintStore/ProcessFootprintTiming are COMPILED here rather than only read as strings
# (2026-09-02). The sampling pass itself still cannot be driven from a harness - it walks the real
# process table and reads a real roster - so what the two files were asserted with was source-string
# locks, and those say a line is present rather than what it computes. One step of the pass IS
# reachable on its own, being handed everything it needs: what every card says once every card has
# been read (`painted`, footprintpaintchecks.swift). Measured before it was written: with that step
# gutted to `return ([:], [:])` this whole suite stayed green.
#
# SessionProcessGroups/MachineLoadRollup are the two halves of machine-load attribution: which
# session a re-parented job belongs to, and which project everything else is working in. The second
# is in the list for SessionSidecar.swift as well as for its own checks - the sidecar reads a
# conversation id off `<pid>.transcript` and asks that file whether it IS one.
#
# ProjectPolicy.swift is in the list because a tick lays this project's launch profile over the
# app policy it re-reads (UsageBarCLI/ProjectPolicy.swift); GitRepoRoot.swift is the repo identity
# that profile is keyed by, and StatusReport/UsageAdvisor come along because the profile also
# publishes itself into `usagebar status --json`.
#
# PickClaimGate is which build may answer the machine's picks (app-side, so the CLI target does not
# compile it the way it compiles the contract beside it); CaptureLaunch comes with it because that
# gate asks it two things: which flag hands the capability back to a build nobody installed, and how
# long that lasts (`pickClaimOverrideLifetime`).
#
# The Model*/SessionModel/SessionDirectives files are `usagebar model`, which is the same shape one
# axis over: a request file, a tick decision, and the CLI surfaces that write one. LaunchAxisNames
# is the shared effort enumeration both targets compile, and ResuperviseContract is the exec
# contract the self-update tests already assert (it was split out of SelfUpdate.swift).
#
# SessionRosterFreshness is the board's "which supervisor build is watching this" reading, split off
# the store on size; BuildVariant comes with it, being where the installed version it compares
# against is read from (and where the demo fixtures' lagging version is derived from), and
# SupervisorVersionStamp is where that reading comes FROM on a live machine: the build stamped into
# the supervisor's child at spawn, which is the half that reaches supervisors older than the state
# record's own field.
#
# DemoSessions.swift is the session board's capture fixtures (demoboardchecks.swift); DemoUsage and
# the five files after it are what IT needs to compile: the enum those fixtures extend, the usage
# model its account fixtures are built from, the fleet rate and the token sample it fabricates, and
# the localisation the token names go through. That is a bigger dependency than a fixture file
# suggests, and it buys the fixtures being EXERCISED rather than read: what a card would be handed
# is asserted directly, which is the only way to state that no field of a real session survives
# onto a screenshot. The two other suites that compile DemoUsage.swift need none of this, which is
# why the session fixtures are a file of their own.
#
# The HostHealth* files are the machine-health watch, and they are here for two different reasons.
# The supervisor's own tick runs its knock station (HostHealthKnock.swift), and the footprint timer
# this suite already compiles is what drives the app-side sampler, so ProcessFootprintTiming.swift
# will not build without the monitor behind it. SystemAlert.swift comes with the monitor, being the
# one notification call it makes.
# The tmux priority guard (TmuxPriority*.swift) is compiled here for the same reason: the footprint timer ticks it.
#
# Usage.swift is compiled for two string constants rather than for any behaviour: `usagebar help` is
# the surface `usagebar send` had to be added to, and the assertion that it WAS is a string check
# (sessionsendverbchecks.swift). The statusline suite owns the other half of that contract - that
# every command the text documents is a command the dispatch answers.
#
# TrustSeed.swift and TrustSeedRelaunch.swift are here because the spawn loop now seeds this
# folder's trust into the home it is launching onto (2026-09-03): the act itself is asserted next
# to its neighbours in tests/addshare, and what this suite compiles them for is the audit line and
# the fact that Supervisor.swift will not build without them.
#
# PreSpawnHook.swift is here for the same reason: both spawn gates call it (issue #7). Its own
# behaviour is asserted in tests/prespawn against a real /bin/sh.
set -euo pipefail
cd "$(dirname "$0")/.."
# Legacy presence fixtures use this process as a real usagebar owner.
# Named after BrandPaths.cliName: a legacy presence entry counts as live only when its process's
# accounting name is the CLI's (supervisorPresenceIsLive, ReloadRequest.swift), and the fixtures
# below stand this very binary up as that process.
out=$(mktemp -d)/usagebar
swiftc UsageBar/Core/BrandPaths.swift UsageBarCLI/BrimCLIGate.swift -o "$out" tests/supervisor/main.swift tests/supervisor/supervisormainchecks.swift \
  tests/supervisor/reloadchecks.swift tests/supervisor/relaunchfoldchecks.swift \
  tests/supervisor/capgatechecks.swift tests/supervisor/capresetchecks.swift \
  tests/supervisor/capselfupdatechecks.swift tests/supervisor/capresumecarrychecks.swift \
  tests/supervisor/caphandoffrunwaychecks.swift tests/supervisor/selfupdatebackgroundchecks.swift \
  tests/supervisor/caplimitresetchecks.swift \
  tests/supervisor/forkchecks.swift tests/supervisor/requesttranscriptchecks.swift \
  tests/supervisor/requestforwardchecks.swift tests/supervisor/transcriptidentitychecks.swift \
  tests/supervisor/dispatchlayoutchecks.swift tests/supervisor/unmanagedlaunchchecks.swift \
  tests/supervisor/keyboardchecks.swift tests/supervisor/keyboardfocuschecks.swift tests/supervisor/openturnchecks.swift \
  tests/supervisor/terminaldrainchecks.swift \
  tests/supervisor/shimchecks.swift tests/supervisor/stableclaudechecks.swift tests/supervisor/selfupdatefoldchecks.swift \
  tests/supervisor/apprelaunchchecks.swift \
  tests/supervisor/rebalancechecks.swift tests/supervisor/rebalanceclaimchecks.swift \
  tests/supervisor/reservechecks.swift \
  tests/supervisor/windowrepickchecks.swift \
  tests/supervisor/clearancemovechecks.swift \
  tests/supervisor/reloadrepickchecks.swift tests/supervisor/relaunchchecks.swift tests/supervisor/positionalchecks.swift \
  tests/supervisor/safeguardchecks.swift \
  tests/supervisor/followchecks.swift tests/supervisor/pendingnoticechecks.swift \
  tests/supervisor/sessionstatechecks.swift tests/supervisor/loginchecks.swift tests/supervisor/sessionorderchecks.swift \
  tests/supervisor/supervisorfreshnesschecks.swift \
  tests/supervisor/launchrecordchecks.swift UsageBarCLI/SessionLaunchRecord.swift \
  tests/supervisor/demoboardchecks.swift tests/supervisor/coalescinggatechecks.swift \
  tests/supervisor/processtreechecks.swift tests/supervisor/processtreelinechecks.swift \
  tests/supervisor/processtreecensuschecks.swift \
  tests/supervisor/sessiongroupchecks.swift tests/supervisor/machineloadchecks.swift \
  tests/supervisor/projectloadchecks.swift \
  tests/supervisor/ghostboardchecks.swift \
  tests/supervisor/orphanchecks.swift \
  tests/supervisor/orphanstorechecks.swift tests/supervisor/orphanroundreadchecks.swift \
  tests/supervisor/orphanrecordexpirychecks.swift \
  tests/supervisor/orphanmemorychecks.swift \
  tests/supervisor/footprintchecks.swift \
  tests/supervisor/footprintpaintchecks.swift \
  tests/supervisor/footprintalertchecks.swift tests/supervisor/footprinttrendchecks.swift \
  tests/supervisor/footprinttrendsurfacechecks.swift \
  tests/supervisor/sessioncardedgechecks.swift \
  tests/supervisor/agentrosterchecks.swift \
  tests/supervisor/turnendchecks.swift \
  tests/supervisor/steeringoffchecks.swift tests/supervisor/turnboundarychecks.swift \
  tests/supervisor/wallforecastchecks.swift tests/supervisor/automaticinputchecks.swift \
  tests/supervisor/droughtchecks.swift tests/supervisor/pinprioritychecks.swift \
  tests/supervisor/capresumechecks.swift tests/supervisor/selfswitchresumechecks.swift tests/supervisor/restartwakechecks.swift tests/supervisor/restartowedchecks.swift \
  tests/supervisor/terminaljumpchecks.swift \
  tests/supervisor/sessioninputchecks.swift tests/supervisor/sessionsendchecks.swift \
  tests/supervisor/sessionprojectchecks.swift \
  tests/supervisor/sessionsendverbchecks.swift \
  tests/supervisor/sessionclearchecks.swift tests/supervisor/providerreopenchecks.swift tests/supervisor/codexhandoffchecks.swift tests/supervisor/codexwallchecks.swift UsageBarCLI/CodexWall.swift UsageBarCLI/ProviderReopen.swift tests/supervisor/draftstashchecks.swift \
  tests/supervisor/quotaknockchecks.swift \
  tests/supervisor/dialoggatechecks.swift tests/supervisor/dialoggatereadingchecks.swift \
  tests/supervisor/knockchannelchecks.swift tests/supervisor/knockhookchecks.swift \
  tests/supervisor/waittrackerchecks.swift tests/supervisor/waitanswerchecks.swift \
  tests/supervisor/waitspoolchecks.swift \
  tests/supervisor/contextchecks.swift tests/supervisor/inventorychecks.swift \
  tests/supervisor/resumepromptchecks.swift \
  tests/supervisor/standdownchecks.swift tests/supervisor/switchchecks.swift \
  tests/supervisor/switchrequestchecks.swift tests/supervisor/switchsessionchecks.swift \
  tests/supervisor/switchhookchecks.swift tests/supervisor/sessionpinchecks.swift \
  tests/supervisor/capsessionpinchecks.swift \
  tests/supervisor/doubleheadchecks.swift tests/supervisor/secondheadswitchchecks.swift tests/supervisor/tasklistpinchecks.swift \
  tests/supervisor/modelrequestchecks.swift tests/supervisor/modeltickchecks.swift \
  tests/supervisor/modelsurfacechecks.swift tests/supervisor/nativemodelchecks.swift \
  tests/supervisor/mcppickerchecks.swift tests/supervisor/accountwindowchecks.swift tests/supervisor/pickerchecks.swift tests/supervisor/pickgracechecks.swift \
  tests/supervisor/pickclaimchecks.swift tests/supervisor/pickheightchecks.swift \
  tests/supervisor/pickpalettechecks.swift tests/supervisor/pickrowchecks.swift \
  tests/supervisor/pickcirclechecks.swift \
  tests/supervisor/picksurfacechecks.swift tests/supervisor/pickmodifierchecks.swift \
  tests/supervisor/usagebarpromptchecks.swift \
  tests/supervisor/transcriptcatchupchecks.swift \
  tests/supervisor/backstopchecks.swift \
  tests/supervisor/codexmonitoringchecks.swift tests/supervisor/codexinputchecks.swift tests/supervisor/codexresumechecks.swift \
  tests/supervisor/codexstartupptychecks.swift UsageBarCLI/CodexStartupChoice.swift UsageBarCLI/CodexStartupChoiceCommand.swift \
  UsageBar/Core/CodexSessionHooks.swift UsageBarCLI/CodexStartMode.swift UsageBarCLI/CodexInputRelay.swift UsageBarCLI/CodexStartupScreen.swift UsageBarCLI/CodexSessionInput.swift UsageBarCLI/CodexSupervisor.swift UsageBarCLI/CodexSessionEvents.swift UsageBarCLI/CodexSessionContext.swift UsageBarCLI/CodexSessionHook.swift \
  UsageBarCLI/Supervisor.swift UsageBarCLI/TaskListPin.swift UsageBarCLI/SupervisorTermination.swift UsageBarCLI/SupervisorRuntime.swift UsageBar/Core/ClaudeStableExecutable.swift UsageBarCLI/CapRecovery.swift UsageBarCLI/RelaunchPlan.swift UsageBarCLI/LaunchFlags.swift UsageBarCLI/LaunchDecision.swift UsageBarCLI/Quarantine.swift UsageBarCLI/LaunchDir.swift UsageBarCLI/CapDetection.swift UsageBarCLI/DriftMonitor.swift \
  UsageBarCLI/TranscriptWatcher.swift UsageBarCLI/TranscriptWatcherScan.swift UsageBarCLI/RestartLiveWork.swift UsageBarCLI/TranscriptLineView.swift UsageBarCLI/TranscriptLineRust.swift UsageBarCLI/TranscriptLineBytes.swift UsageBarCLI/TranscriptLoginSignals.swift UsageBar/Core/LimitReset.swift UsageBarCLI/LimitResetSignals.swift UsageBarCLI/CapLimitReset.swift UsageBarCLI/SessionQuiet.swift UsageBarCLI/TranscriptSignals.swift UsageBarCLI/NativeModelCommand.swift UsageBarCLI/TranscriptFork.swift UsageBarCLI/RequestTranscript.swift UsageBarCLI/TranscriptIdentity.swift UsageBarCLI/Snapshot.swift UsageBarCLI/CodexLaunchArgs.swift UsageBarCLI/AccountPick.swift UsageBarCLI/AccountPick+Handoff.swift \
  UsageBarCLI/AccountBinding.swift UsageBarCLI/AccountReserveReader.swift UsageBar/Core/AccountReserve.swift \
  UsageBarCLI/Reload.swift UsageBarCLI/ReloadSelf.swift \
  UsageBar/Core/ChromeSettingSignal.swift \
  UsageBar/Core/SessionMonitoring.swift UsageBarCLI/ReloadRequest.swift UsageBarCLI/SelfUpdate.swift UsageBarCLI/AppRelaunch.swift UsageBarCLI/AppRelaunchLog.swift \
  UsageBarCLI/AccountComfort.swift \
  UsageBarCLI/Rebalance.swift UsageBarCLI/MoveField.swift UsageBarCLI/WindowRepick.swift UsageBarCLI/WindowRepickWindow.swift UsageBarCLI/SafeguardDrift.swift UsageBarCLI/ModelDegradation.swift \
  UsageBarCLI/AutoSteering.swift UsageBarCLI/TurnBoundaryMove.swift UsageBarCLI/WallForecast.swift UsageBarCLI/LiveSessionCount.swift UsageBarCLI/DroughtWatch.swift \
  UsageBarCLI/CapResume.swift UsageBarCLI/CapResumeLog.swift UsageBarCLI/SelfSwitchResume.swift UsageBarCLI/RestartWake.swift \
  UsageBarCLI/KeyboardIdle.swift UsageBarCLI/FocusEvents.swift UsageBarCLI/KeyboardTrace.swift UsageBarCLI/OpenTurn.swift UsageBarCLI/ProviderExecutable.swift \
  UsageBarCLI/LaunchResume.swift UsageBarCLI/LastConversation.swift UsageBarCLI/UnmanagedLaunch.swift \
  UsageBarCLI/TerminalHandover.swift \
  UsageBarCLI/PendingNotice.swift UsageBarCLI/SessionState.swift UsageBarCLI/CodexStartupScreenRecord.swift UsageBarCLI/UserNotice.swift UsageBarCLI/SessionTurnEnd.swift UsageBarCLI/HookNotify.swift UsageBarCLI/AgentRoster.swift UsageBarCLI/HookAgents.swift UsageBarCLI/SessionStateSync.swift UsageBarCLI/SessionWaitTracker.swift UsageBarCLI/FollowAdoption.swift UsageBarCLI/StandDown.swift \
  UsageBarCLI/SessionWaitEvent.swift UsageBarCLI/SessionWaitLogic.swift UsageBarCLI/SessionWaitSpool.swift UsageBarCLI/EventDeliverySpawn.swift UsageBarCLI/CodexWaitEvents.swift \
  UsageBar/Core/ProjectStatusLine.swift UsageBarCLI/SessionContext.swift UsageBarCLI/SessionInventory.swift UsageBarCLI/MessagingSocket.swift \
  UsageBarCLI/SessionInput.swift UsageBarCLI/AutomaticInput.swift UsageBarCLI/SessionInputAutomatic.swift UsageBarCLI/SessionInputTick.swift UsageBarCLI/SessionInputLanding.swift \
  UsageBarCLI/SessionInputDraft.swift \
  UsageBarCLI/SessionClear.swift UsageBarCLI/SessionInputLog.swift \
  UsageBarCLI/SessionInputRequest.swift \
  UsageBarCLI/SessionInputCommand.swift UsageBarCLI/SessionInputOccupant.swift \
  UsageBarCLI/SessionProjectAddress.swift \
  UsageBarCLI/SessionSendVerb.swift UsageBarCLI/Usage.swift UsageBarCLI/OverlayCLI.swift \
  UsageBarCLI/MessageVerb.swift UsageBarCLI/NativeMessage.swift \
  UsageBarCLI/SessionAddressLookup.swift \
  UsageBarCLI/ClaudeNativeMessage.swift \
  UsageBarCLI/SessionSendWait.swift \
  UsageBarCLI/QuotaKnock.swift UsageBarCLI/QuotaKnockLogic.swift \
  UsageBarCLI/QuotaKnockNotice.swift UsageBarCLI/QuotaKnockHookContract.swift UsageBarCLI/HookKnock.swift \
  UsageBarCLI/ChromeReach.swift UsageBarCLI/ChromePreflight.swift \
  UsageBarCLI/HostHealthKnock.swift UsageBarCLI/HostHealthKnockLogic.swift \
  UsageBar/Core/HostHealthLogic.swift UsageBar/Core/HostHealthCPU.swift UsageBar/Core/HostHealthReaders.swift \
  UsageBar/Core/HostHealthSessions.swift \
  UsageBar/Core/KeystrokeText.swift \
  UsageBar/Core/HostHealthNaming.swift UsageBar/Core/HostHealthMonitor.swift UsageBar/Core/HostLoadHistory.swift UsageBar/Core/HostLoadHistoryWriter.swift UsageBar/Core/SystemAlert.swift \
  UsageBar/Core/CPUAlertLogic.swift UsageBar/Core/CPUAlertBreakdown.swift UsageBar/Core/CPUAlertReaders.swift UsageBar/Core/CPUAlertCommandLog.swift UsageBar/Core/CPUAlertCommandReaders.swift UsageBar/Core/CPUAlertMonitor.swift \
  UsageBar/Core/TmuxPriorityLogic.swift UsageBar/Core/TmuxPriorityReaders.swift UsageBar/Core/TmuxPriorityMonitor.swift \
  UsageBar/Core/ProcessCPUWatchLogic.swift UsageBar/Core/ProcessCPUWatchReaders.swift UsageBar/Core/ProcessCPUWatchMonitor.swift \
  UsageBarCLI/ResumePrompt.swift UsageBarCLI/SessionSwitch.swift UsageBarCLI/SwitchBadges.swift UsageBarCLI/ManualMoveState.swift UsageBarCLI/SwitchDecision.swift UsageBarCLI/SwitchRequest.swift UsageBarCLI/SessionAddressing.swift UsageBarCLI/AccountHome.swift UsageBarCLI/SwitchCommand.swift UsageBarCLI/CodexHandoff.swift UsageBarCLI/CodexHandoffCommand.swift UsageBarCLI/SwitchHook.swift UsageBarCLI/SwitchMenu.swift UsageBarCLI/WorktreeMenu.swift \
  UsageBarCLI/ProjectPolicy.swift UsageBarCLI/GitRepoRoot.swift \
  UsageBarCLI/ResuperviseContract.swift UsageBarCLI/ModelRequest.swift UsageBarCLI/SessionModel.swift \
  UsageBarCLI/ChildReaper.swift UsageBarCLI/HandoffKill.swift UsageBarCLI/HandoffResume.swift \
  UsageBarCLI/SessionDirectives.swift UsageBarCLI/ModelCommand.swift UsageBarCLI/ModelHook.swift \
  UsageBarCLI/ModelMenu.swift UsageBar/Core/LaunchAxisNames.swift \
  UsageBarCLI/MCPServe.swift UsageBarCLI/MCPPicker.swift UsageBarCLI/MCPAccountOffer.swift UsageBarCLI/MCPPickOffer.swift UsageBarCLI/UsageBarPrompt.swift UsageBarCLI/NativePick.swift UsageBarCLI/PickRows.swift UsageBar/Core/PickContract.swift \
  UsageBar/Core/PickPanelMetrics.swift UsageBar/Core/PickPalette.swift UsageBar/Core/PickKeyboard.swift UsageBar/Core/PanelGeometry.swift UsageBarCLI/PromptHookBackstop.swift \
  UsageBar/Core/PickClaimGate.swift UsageBar/Core/CaptureLaunch.swift \
  UsageBar/Core/PromptHookInput.swift \
  UsageBarCLI/MCPAuthSync.swift UsageBarCLI/MCPAuthMerge.swift UsageBarCLI/MCPSeedGate.swift UsageBarCLI/KeychainSecret.swift \
  UsageBarCLI/KeychainPartitionRepair.swift \
  UsageBar/Core/Keychain/KeychainReader.swift UsageBar/Core/Keychain/ClaudeKeychainService.swift \
  UsageBar/Core/ClaudeStatePath.swift UsageBar/Core/PathIdentity.swift \
  UsageBar/Core/TrustSeed.swift UsageBarCLI/TrustSeedRelaunch.swift UsageBarCLI/PreSpawnHook.swift \
  UsageBarCLI/StatusReport.swift UsageBar/Core/HeldOverReset.swift UsageBarCLI/UsageAdvisor.swift UsageBarCLI/UsageAdvisorMath.swift \
  UsageBar/Core/TerminalJump.swift UsageBar/Stores/TerminalJumpNotice.swift UsageBar/Core/TerminalJumpScript.swift UsageBar/Core/CLIRunner.swift UsageBar/Core/CLISearchPath.swift UsageBar/Stores/SessionRosterStore.swift \
  UsageBar/Stores/SessionRosterScan.swift UsageBar/Stores/SessionRosterArrangement.swift UsageBar/Stores/ReloadReadinessStore.swift UsageBar/Core/CoalescingGate.swift \
  UsageBar/Stores/SessionRosterFreshness.swift UsageBar/Core/BuildVariant.swift \
  UsageBar/Core/SupervisorVersionStamp.swift \
  UsageBar/Core/SessionSidecar.swift UsageBar/Core/SessionPinScope.swift \
  UsageBar/Core/SessionBoardOrder.swift UsageBar/Core/ProcessTreeStats.swift UsageBar/Core/ProcessTreePool.swift UsageBar/Core/ProcessTreeRates.swift \
  UsageBar/Core/ProcessTreeLine.swift UsageBar/Core/ProcessTreeCensus.swift \
  UsageBar/Core/SessionProcessGroups.swift UsageBar/Core/SessionProcessGroupsFile.swift UsageBar/Core/MachineLoadRollup.swift \
  UsageBar/Core/MachineLoadReaders.swift \
  UsageBar/Core/SessionBoardGhosts.swift \
  UsageBar/Stores/ProjectLoadAccounting.swift \
  UsageBar/Stores/ProcessFootprintStore.swift UsageBar/Stores/ProcessFootprintTiming.swift \
  UsageBar/Stores/ProcessFootprintPass.swift UsageBar/Core/FootprintMachineRead.swift \
  UsageBar/Core/OrphanReclaim.swift UsageBar/Core/OrphanVerdict.swift \
  UsageBar/Core/OrphanLease.swift UsageBar/Core/OrphanKill.swift \
  UsageBar/Core/OrphanReaders.swift UsageBar/Core/OrphanNotice.swift \
  UsageBar/Stores/OrphanReclaimStore.swift UsageBar/Stores/OrphanReclaimStoreSweep.swift \
  UsageBar/Stores/OrphanReclaimRoundReads.swift \
  UsageBar/Stores/OrphanReclaimStoreEntries.swift \
  UsageBar/Core/ProcessTreeReaders.swift UsageBar/Core/FootprintAlerts.swift \
  UsageBar/Core/FootprintTrend.swift UsageBar/Core/FootprintPeak.swift UsageBar/Core/MotionStyle.swift \
  UsageBar/Core/DemoSessions.swift UsageBar/Core/DemoUsage.swift UsageBar/Core/DemoManyAccounts.swift \
  UsageBar/Providers/ProviderModels.swift UsageBar/Core/FleetForecast.swift \
  UsageBar/Core/UsageHistory.swift UsageBar/Core/TokenStats/TokenTotals.swift \
  UsageBar/Core/AppLocale.swift
"$out"

python3 tests/supervisor/codexinputpty.py "$out"
python3 tests/supervisor/codexresumepty.py "$out"
python3 tests/supervisor/codexstartuppty.py "$out"
