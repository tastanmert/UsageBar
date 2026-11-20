#!/bin/bash
# The shared layer of the usage-tab preview layouts (-UsageBarUsageLayout ledger|tray, B-2625): the
# tightest-window rule (LaunchPolicyStore.bindingWindow, with headroom held to its old values), the
# flag reader in a DEBUG and a non-DEBUG build, and text locks on the SwiftUI files that cannot be
# compiled here. No Xcode test target needed; exits non-zero on failure.
#
# The source list is LaunchPolicyStore's transitive closure, the same one run-integrations-tests.sh
# compiles for it minus the Integrations* stores, plus the demo fixtures (the equivalence check runs
# over them).
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
swiftc UsageBar/Core/BrandPaths.swift -target "$(uname -m)-apple-macos14.0" -o "$out/run" tests/usagelayout/main.swift \
  UsageBar/Core/UsageLayout.swift UsageBar/Core/UsageLayoutMath.swift UsageBar/Core/FleetMath.swift UsageBar/Core/PanelGeometry.swift \
  UsageBar/Stores/LaunchPolicyStore.swift UsageBar/Stores/LaunchPolicyStore+AutoPick.swift UsageBar/Stores/LaunchPolicyScoring.swift \
  UsageBar/Views/UsageFormatting.swift UsageBar/Stores/DisplaySettings.swift \
  UsageBar/Core/AccountReserve.swift UsageBar/Core/PersonalAccount.swift \
  UsageBarCLI/AccountComfort.swift UsageBarCLI/Quarantine.swift \
  UsageBarCLI/QuotaKnockHookContract.swift \
  UsageBarCLI/SessionState.swift UsageBarCLI/CodexStartupScreenRecord.swift UsageBarCLI/AgentRoster.swift UsageBar/Core/SessionMonitoring.swift UsageBarCLI/ReloadRequest.swift \
  UsageBar/Core/UsageSnapshot.swift \
  UsageBar/Core/AppLocale.swift UsageBar/Providers/ProviderModels.swift \
  UsageBar/Core/DemoUsage.swift UsageBar/Core/DemoManyAccounts.swift UsageBar/Core/LimitReset.swift UsageBar/Core/BuildVariant.swift UsageBar/Core/FleetForecast.swift UsageBar/Core/UsageHistory.swift \
  UsageBar/Core/TokenStats/TokenTotals.swift \
  UsageBarCLI/UsageAdvisor.swift UsageBarCLI/UsageAdvisorMath.swift \
  UsageBar/Core/ProcessTreeStats.swift UsageBar/Core/ProcessTreePool.swift UsageBar/Core/ProcessTreeRates.swift UsageBar/Core/ProcessTreeLine.swift \
  UsageBar/Core/FootprintAlerts.swift UsageBar/Core/PickContract.swift
"$out/run"

# The flag end to end: the argument domain is what the app reads. DEBUG honours it, a build without
# DEBUG never does, and a value that names no layout is the default layout either way.
swiftc -DDEBUG -o "$out/debug" tests/usagelayout/flag.swift UsageBar/Core/UsageLayout.swift
swiftc -o "$out/plain" tests/usagelayout/flag.swift UsageBar/Core/UsageLayout.swift
EXPECT=ledger "$out/debug" -UsageBarUsageLayout ledger
EXPECT=tray "$out/debug" -UsageBarUsageLayout Tray
EXPECT=nil "$out/debug" -UsageBarUsageLayout orbit
EXPECT=nil "$out/debug"
EXPECT=nil "$out/plain" -UsageBarUsageLayout ledger
EXPECT=nil "$out/plain" -UsageBarUsageLayout tray
