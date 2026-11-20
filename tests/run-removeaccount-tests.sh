#!/bin/bash
# Compiles the "remove an account" core (UsageBar/Core/RemoveAccount.swift, plus AddAccount.swift for
# the config-home naming both acts share) with a small assertion harness and runs it. No Xcode test
# target needed; exits non-zero on failure.
#
# Nothing here moves a folder: the Trash is injected, so the suite never touches the Trash of the
# machine running it. ClaudeOnboarding.swift is here for AddAccount.swift alone: its marker sweep
# leaves the first-run wizard's note as it clears, and nothing in this suite calls either.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -o "$out" tests/removeaccount/main.swift \
  UsageBar/Core/RemoveAccount.swift UsageBar/Core/AddAccount.swift \
  UsageBar/Core/AccountRemovals.swift \
  UsageBar/Core/SharedHarness.swift UsageBar/Core/PathIdentity.swift \
  UsageBar/Core/TrustSeed.swift UsageBar/Core/ClaudeStatePath.swift \
  UsageBar/Core/ClaudeOnboarding.swift \
  UsageBar/Core/Keychain/KeychainReader.swift UsageBar/Core/Keychain/ClaudeKeychainService.swift
"$out"
