#!/bin/bash
# Compiles the shell-profile block surgery (IntegrationsStore) together with a small
# assertion harness and runs it. No Xcode test target needed; exits non-zero on failure.
#
# The source list is that store's transitive closure, so it follows the app target's (project.yml),
# which reaches outside UsageBar/ for the advisor: UsageAdvisor.swift lives in the CLI folder, both
# targets compile the one copy, and the demo fixtures in DemoUsage.swift name it. The share engine
# and the account discovery behind it joined that closure when the store grew the "Shared harness"
# row (2026-08-13): the row's word is read off the filesystem for every account, so the store now
# reaches the same core `usagebar share` does.
#
# AND THE FOOTPRINT JOINED IT THROUGH THE FIXTURES, which is the last four files: DemoUsage paints a
# session card's readings as well as its account gauges, so it names ProcessFootprint, the alert
# tiers it sets on one, and the line those are spelled into (ProcessTreeLine, whose separator is
# PickContract's). The list had drifted behind that and this suite would not compile at all; a
# closure is only a closure while every name in it is followed.
# AND THE LAUNCH POLICY STORE JOINED IT WITH THE ARTIFACT ROW (2026-08-20): that row's install
# seeds the account the guard reads out of ~/.usagebar/state.json, which is the difference between a
# row that says Installed and a row that does anything at all, so the store that owns that file is
# now part of this store's closure (AccountComfort and Quarantine come in behind it, exactly as they
# do in the app target), along with its own two halves: the burn-rate scoring it was split from for
# file size, and the per-account block it publishes (AccountReserve.swift - the personal account and
# the reserve the Artifact seed now reads before it guesses). PersonalAccount.swift joined them with
# the flagship water line (2026-09-05): it is the app's translation of that ruling into the meters'
# own vocabulary, and this is the only suite that can ask it for a value rather than read its text.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift UsageBar/Core/LegacyIdentifierMigration.swift -o "$out" tests/integrations/main.swift tests/integrations/usagebarcommandchecks.swift \
  tests/integrations/statuslinechecks.swift tests/integrations/settingseditchecks.swift \
  tests/integrations/agenthookchecks.swift tests/integrations/knockhookchecks.swift tests/integrations/artifacthookchecks.swift tests/integrations/autofollowchecks.swift tests/integrations/notificationhookchecks.swift tests/integrations/switchgroupchecks.swift tests/integrations/selfhealchecks.swift \
  tests/integrations/localizationchecks.swift tests/integrations/skillfolderchecks.swift \
  tests/integrations/nativepickerchecks.swift tests/integrations/skillversionchecks.swift \
  tests/integrations/shimscriptchecks.swift tests/integrations/sharedharnesschecks.swift \
  tests/integrations/completionchecks.swift tests/integrations/clitoolchecks.swift \
  tests/integrations/smartbadgechecks.swift tests/integrations/loadbadgechecks.swift tests/integrations/sharedloginbadgechecks.swift \
  tests/integrations/claudejsonformatchecks.swift tests/integrations/profilechecks.swift UsageBar/Core/SharedLogin.swift \
  tests/integrations/projectstatuslinechecks.swift UsageBar/Core/ProjectStatusLine.swift \
  UsageBar/Core/CodexSessionHooks.swift UsageBar/Stores/IntegrationsCodexSession.swift \
  UsageBar/Stores/IntegrationsStore.swift UsageBar/Stores/IntegrationsBackup.swift UsageBar/Core/ClaudeJSONFormat.swift UsageBar/Stores/IntegrationsShim.swift \
  UsageBar/Stores/IntegrationsCLITool.swift \
  UsageBar/Stores/IntegrationsSharedHarness.swift \
  UsageBar/Core/ShareExisting.swift UsageBar/Core/SharedHarness.swift UsageBar/Core/PathIdentity.swift \
  UsageBar/Core/AddAccount.swift \
  UsageBar/Core/AddAccountFlow.swift UsageBar/Core/TrustSeed.swift UsageBar/Core/ClaudeOnboarding.swift \
  UsageBar/Core/RemoveAccount.swift UsageBar/Providers/Codex/CodexAccounts.swift \
  UsageBar/Stores/IntegrationsCompletion.swift \
  UsageBar/Stores/IntegrationsSkill.swift \
  UsageBar/Core/Harness/*.swift \
  UsageBar/Stores/IntegrationsSkillContent.swift UsageBar/Stores/IntegrationsSkillFolderMove.swift \
  UsageBar/Stores/IntegrationsUsageBarCommand.swift UsageBar/Stores/IntegrationsPromptCommand.swift \
  UsageBar/Stores/IntegrationsPromptHook.swift UsageBar/Stores/IntegrationsMCPServer.swift \
  UsageBar/Stores/IntegrationsNotificationHook.swift \
  UsageBar/Stores/IntegrationsAgentHook.swift \
  UsageBar/Stores/IntegrationsKnockHook.swift UsageBar/Stores/IntegrationsAutoFollow.swift \
  UsageBar/Stores/IntegrationsArtifactHook.swift \
  UsageBar/Stores/LaunchPolicyStore.swift UsageBar/Stores/LaunchPolicyStore+AutoPick.swift UsageBar/Stores/LaunchPolicyScoring.swift \
  UsageBar/Views/UsageFormatting.swift UsageBar/Stores/DisplaySettings.swift \
  UsageBar/Core/AccountReserve.swift UsageBar/Core/PersonalAccount.swift \
  UsageBarCLI/AccountComfort.swift UsageBarCLI/Quarantine.swift \
  UsageBarCLI/QuotaKnockHookContract.swift \
  UsageBarCLI/SessionState.swift UsageBarCLI/CodexStartupScreenRecord.swift UsageBarCLI/AgentRoster.swift UsageBar/Core/SessionMonitoring.swift UsageBarCLI/ReloadRequest.swift \
  UsageBar/Stores/IntegrationsSelfHeal.swift \
  UsageBar/Core/PromptHookInput.swift UsageBar/Core/CLIRunner.swift UsageBar/Core/CLISearchPath.swift UsageBar/Core/ClaudeStableExecutable.swift \
  UsageBar/Core/UsageSnapshot.swift \
  UsageBar/Core/AppLocale.swift UsageBar/Providers/ProviderModels.swift \
  UsageBar/Core/DemoUsage.swift UsageBar/Core/DemoManyAccounts.swift UsageBar/Core/LimitReset.swift UsageBar/Core/BuildVariant.swift UsageBar/Core/FleetForecast.swift UsageBar/Core/UsageHistory.swift \
  UsageBar/Core/TokenStats/TokenTotals.swift \
  UsageBarCLI/UsageAdvisor.swift UsageBarCLI/UsageAdvisorMath.swift \
  UsageBar/Providers/Claude/ClaudeAccounts.swift UsageBar/Core/Keychain/KeychainReader.swift \
  UsageBar/Core/Keychain/ClaudeKeychainService.swift UsageBar/Core/ClaudeStatePath.swift \
  UsageBar/Core/AccountDirWatcher.swift UsageBar/Core/CoalescingGate.swift UsageBar/Core/AccountHomeListing.swift \
  UsageBar/Core/ProcessTreeStats.swift UsageBar/Core/ProcessTreePool.swift UsageBar/Core/ProcessTreeRates.swift UsageBar/Core/ProcessTreeLine.swift \
  UsageBar/Core/FootprintAlerts.swift UsageBar/Core/PickContract.swift
test_home=$(mktemp -d)
HOME="$test_home" CFFIXED_USER_HOME="$test_home" "$out"
