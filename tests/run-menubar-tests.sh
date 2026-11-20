#!/bin/bash
# Compiles the menu-bar strip's segment builders (UsageBar/Core/MenuBarSegments.swift) together with
# the fleet math they pool through and a small assertion harness, and runs it. No Xcode test target
# needed; exits non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc -o "$out" tests/menubar/main.swift tests/menubar/plansplitchecks.swift tests/menubar/resetpassedchecks.swift tests/menubar/statusfacechecks.swift tests/menubar/ringchecks.swift tests/menubar/showsessionchecks.swift tests/menubar/brandchecks.swift UsageBar/Core/ProviderBrand.swift UsageBar/Core/PoolRing.swift UsageBar/Core/MenuBarSegments.swift UsageBar/Core/FleetMath.swift \
    UsageBar/Providers/ProviderModels.swift UsageBar/Stores/DisplaySettings.swift \
    UsageBar/Core/HeldOverReset.swift UsageBar/Core/HeldOverResetUsage.swift
"$out"
