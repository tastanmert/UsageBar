#!/bin/bash
# Compiles the shared "add an account" core (UsageBar/Core/AddAccount.swift + SharedHarness.swift +
# ShareExisting.swift + TrustSeed.swift, which BOTH targets build) together with a small assertion
# harness and runs it.
# No Xcode test target needed; exits non-zero on failure.
#
# The Keychain files are compiled, never called: every assertion injects its own probe, so the
# suite reads no Keychain and depends on no login existing on the machine running it.
# ClaudeOnboarding.swift comes along because AddAccount.swift's marker sweep leaves the first-run
# wizard's note as it clears; the sweep assertions here are codex ones, which it declines.
set -euo pipefail
cd "$(dirname "$0")/.."
#
# The CLI half of `usagebar share` joined that list (2026-08-13): what the command reads a line as is
# a refusal rule, and the thing it refuses (`usagebar share codex work --help`) used to MOVE that
# account's files - so it is asserted behaviourally rather than as text, the way `switchIntent` is.
# The five files after ShareCommand.swift are simply its transitive closure.
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -o "$out" tests/addshare/main.swift tests/addshare/shareexistingchecks.swift \
  tests/addshare/sharelinkedstorechecks.swift \
  tests/addshare/unlinkchecks.swift tests/addshare/harnessfixtures.swift \
  tests/addshare/sharecommandchecks.swift tests/addshare/trustrelaunchchecks.swift \
  UsageBar/Core/AddAccount.swift UsageBar/Core/SharedHarness.swift UsageBar/Core/ShareExisting.swift \
  UsageBar/Core/PathIdentity.swift UsageBar/Core/TrustSeed.swift \
  UsageBar/Core/AddAccountFlow.swift UsageBar/Core/ClaudeOnboarding.swift \
  UsageBar/Core/Keychain/KeychainReader.swift UsageBar/Core/Keychain/ClaudeKeychainService.swift \
  UsageBar/Core/ClaudeStatePath.swift \
  UsageBarCLI/ShareCommand.swift \
  UsageBarCLI/Snapshot.swift UsageBar/Core/ClaudeStableExecutable.swift UsageBarCLI/CodexLaunchArgs.swift UsageBarCLI/AccountPick.swift UsageBarCLI/AccountPick+Handoff.swift \
  UsageBarCLI/AccountBinding.swift UsageBarCLI/AccountReserveReader.swift UsageBar/Core/AccountReserve.swift \
  UsageBarCLI/AccountComfort.swift \
  UsageBarCLI/ResumePrompt.swift UsageBarCLI/ProviderExecutable.swift
"$out"
