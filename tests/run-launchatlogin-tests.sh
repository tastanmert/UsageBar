#!/bin/bash
# Compiles the "Start at login" row's decision layer with a small assertion harness and runs it:
# the SMAppService status mapping and the failure rules (UsageBar/Core/LaunchAtLoginState.swift,
# UsageBar/Core/LaunchAtLoginService.swift) and the dev state preview behind -UsageBarLoginItemPreview
# (UsageBar/Core/LoginItemPreview.swift). No SwiftUI and no Xcode test target; the row that draws all
# of it is UsageBar/Views/SettingsLaunchAtLoginRow.swift.
#
# Nothing here registers a login item or touches the machine's own: every state is named as an enum
# value, so the mapping, the sentences and the preview walks are asserted without a single write.
#
# The trailing file list is DemoUsage's transitive closure, which the preview's build gate reaches
# through (the same closure run-integrations-tests.sh compiles, and for the same reason: one copy
# of "is this a demo launch", not a second spelling of the flag).
#
# THAT CLOSURE NOW REACHES THE FOOTPRINT, which is the last four files: the fixtures paint a session
# card's readings as well as its account gauges, so DemoUsage names ProcessFootprint, the alert
# tiers it sets on one, and the line those are spelled into (ProcessTreeLine, whose separator is
# PickContract's). The list had drifted behind that and this suite would not compile at all; a
# closure is only a closure while every name in it is followed.
#
# The deployment target is pinned because SMAppService starts at macOS 13 and a bare swiftc would
# leave it to the host's default. Exits non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -target "$(uname -m)-apple-macos14.0" -o "$out" tests/launchatlogin/main.swift \
  tests/launchatlogin/launchatloginchecks.swift \
  UsageBar/Core/LaunchAtLoginState.swift UsageBar/Core/LaunchAtLoginService.swift \
  UsageBar/Core/LaunchAtLoginDefault.swift \
  UsageBar/Core/LoginItemPreview.swift UsageBar/Core/CaptureLaunch.swift \
  UsageBar/Core/BuildVariant.swift UsageBar/Core/DemoUsage.swift UsageBar/Core/DemoManyAccounts.swift UsageBar/Core/LimitReset.swift UsageBar/Core/UsageSnapshot.swift \
  UsageBar/Core/AppLocale.swift UsageBar/Core/FleetForecast.swift UsageBar/Core/UsageHistory.swift \
  UsageBar/Core/TokenStats/TokenTotals.swift \
  UsageBar/Providers/ProviderModels.swift UsageBarCLI/UsageAdvisor.swift \
  UsageBarCLI/UsageAdvisorMath.swift \
  UsageBar/Core/ProcessTreeStats.swift UsageBar/Core/ProcessTreePool.swift UsageBar/Core/ProcessTreeRates.swift UsageBar/Core/ProcessTreeLine.swift \
  UsageBar/Core/FootprintAlerts.swift UsageBar/Core/PickContract.swift
"$out"
