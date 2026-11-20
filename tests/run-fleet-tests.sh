#!/bin/bash
# Compiles the fleet aggregation math (UsageBar/Core/FleetMath.swift) together with a small
# assertion harness and runs it. No Xcode test target needed; exits non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -o "$out" tests/fleet/main.swift tests/fleet/plansplit.swift tests/fleet/capweightchecks.swift UsageBar/Core/UsageSnapshot.swift UsageBar/Core/FleetMath.swift UsageBar/Core/FleetTooltip.swift UsageBar/Core/FleetForecast.swift \
    UsageBar/Core/UsageHistory.swift UsageBar/Providers/ProviderModels.swift UsageBar/Stores/DisplaySettings.swift
"$out"
