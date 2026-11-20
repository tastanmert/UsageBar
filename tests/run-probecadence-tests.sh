#!/bin/bash
# Compiles the Claude probe cadence (UsageBar/Core/ProbeCadence.swift) with a small assertion harness
# and runs it. No Xcode test target needed; exits non-zero on failure.
#
# ReloadRequest.swift and SessionMonitoring.swift come along for the live-supervisor check the
# cadence reads. The store that runs the rounds cannot be compiled in here, so the harness reads it
# as text to assert the wiring, the same arrangement the last-good and account-row suites use.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/RefreshFailureLog.swift UsageBar/Core/BrandPaths.swift -o "$out" tests/probecadence/main.swift \
  UsageBar/Core/ProbeCadence.swift UsageBar/Providers/ProviderModels.swift \
  UsageBarCLI/ReloadRequest.swift UsageBarCLI/LiveRates.swift UsageBar/Core/SessionMonitoring.swift
"$out"
