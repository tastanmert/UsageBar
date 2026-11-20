#!/bin/bash
# Compiles the held-over reset judge (UsageBar/Core/HeldOverReset.swift) and its app wrapper with a
# small assertion harness and runs it. No Xcode test target needed; exits non-zero on failure.
#
# LastGoodFold.swift comes along for the replay: the state under test is exactly what that fold
# publishes after failed polls. Run from the repo root, which the cd below guarantees.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -o "$out" tests/resetpassed/main.swift UsageBar/Core/HeldOverReset.swift \
  UsageBar/Core/HeldOverResetUsage.swift UsageBar/Providers/ProviderModels.swift \
  UsageBar/Core/LastGoodFold.swift UsageBar/Core/UsageSnapshot.swift
"$out"
