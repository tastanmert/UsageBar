#!/bin/bash
# Compiles the status line's rate-limit facts (UsageBarCLI/LiveRates.swift) and the cadence and overlay
# that read them (UsageBar/Core/ProbeCadence.swift) with a small assertion harness and runs it. No Xcode
# test target needed; exits non-zero on failure.
#
# The status line and the project file cannot be compiled in here, so the harness reads them as
# text to assert the wiring, the same arrangement the probe-cadence suite uses for the store.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -o "$out" tests/liverates/main.swift \
  UsageBarCLI/LiveRates.swift UsageBar/Core/ProbeCadence.swift UsageBar/Providers/ProviderModels.swift \
  UsageBarCLI/ReloadRequest.swift UsageBar/Core/SessionMonitoring.swift
"$out"
