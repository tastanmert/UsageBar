#!/bin/bash
# Compiles the CPU watch's pure half (CPUAlertLogic, CPUAlertBreakdown, CPUAlertCommandLog) with
# KeystrokeText.swift and an assertion harness, and runs it. Foundation only, no Xcode target; exits non-zero on failure.
# The end of the harness reads the monitor, readers and timer sources as text for the structural
# promises a pure harness cannot drive (clock throttle, no timer of its own, the process scan
# confined to the announcing branch, names never argv, every string translated).
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -o "$out" tests/cpualert/main.swift tests/cpualert/breakdownchecks.swift \
  tests/cpualert/realsamplechecks.swift tests/cpualert/commandlogchecks.swift UsageBar/Core/CPUAlertLogic.swift \
  UsageBar/Core/CPUAlertBreakdown.swift UsageBar/Core/CPUAlertCommandLog.swift UsageBar/Core/KeystrokeText.swift
"$out"
