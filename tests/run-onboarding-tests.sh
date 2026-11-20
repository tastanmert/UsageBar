#!/bin/bash
# Compiles the first-run-wizard seed (UsageBar/Core/ClaudeOnboarding.swift) with a small assertion
# harness and runs it. No Xcode test target needed; exits non-zero on failure.
#
# AddAccount.swift and its Foundation-only neighbours come along for two symbols the seed shares
# rather than restates: the provider's config-home base name and the rule for where the default
# home keeps its state file. Nothing in here reads a Keychain or a real config home - every
# assertion runs against a fake home directory the harness builds itself.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -o "$out" tests/onboarding/main.swift \
  UsageBar/Core/ClaudeOnboarding.swift UsageBar/Core/ClaudeStatePath.swift \
  UsageBar/Core/AddAccount.swift UsageBar/Core/SharedHarness.swift UsageBar/Core/PathIdentity.swift \
  UsageBar/Core/TrustSeed.swift \
  UsageBar/Core/Keychain/KeychainReader.swift UsageBar/Core/Keychain/ClaudeKeychainService.swift
"$out"
