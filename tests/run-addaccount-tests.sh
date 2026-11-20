#!/bin/bash
# Compiles the add-account chain (UsageBar/Core/AddAccount.swift + the login runner it hands the new
# home to + the watcher rules that turn a finished login into a visible card) with a small assertion
# harness and runs it. Every file is Foundation-only, so nothing else comes along; no Xcode test
# target needed. Exits non-zero on failure.
#
# The login is driven against stub CLIs the harness writes itself, never a real provider login.
# ClaudeOnboarding.swift comes along because AddAccount.swift's marker sweep leaves the first-run
# wizard's note as it clears (it is claude-only and writes to nothing this suite builds).
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -o "$out" tests/addaccount/main.swift \
  UsageBar/Core/AddAccount.swift UsageBar/Core/AddAccountFlow.swift UsageBar/Core/SharedHarness.swift UsageBar/Core/PathIdentity.swift \
  UsageBar/Core/TrustSeed.swift \
  UsageBar/Core/ClaudeOnboarding.swift \
  UsageBar/Core/Keychain/KeychainReader.swift UsageBar/Core/Keychain/ClaudeKeychainService.swift \
  UsageBar/Core/ClaudeStatePath.swift \
  UsageBar/Core/RenewLoginCommand.swift UsageBar/Core/RenewLoginRunner.swift UsageBar/Core/CLISearchPath.swift UsageBar/Core/ClaudeStableExecutable.swift \
  UsageBar/Core/AccountDirWatcher.swift UsageBar/Core/CoalescingGate.swift UsageBar/Providers/ProviderModels.swift \
  UsageBar/Stores/KnownAccountsStore.swift UsageBar/Core/KnownAccounts.swift UsageBar/Core/BuildVariant.swift
"$out"
