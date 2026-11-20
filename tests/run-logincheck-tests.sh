#!/bin/bash
# Compiles the login-expiry alert's decision layer (UsageBar/Core/LoginStatusCommand.swift) together
# with the spawn it runs on (UsageBar/Core/CLIRunner.swift), the renewal knowledge it borrows its
# environment and its ANSI stripping from (UsageBar/Core/RenewLoginCommand.swift), and the memory that
# keeps a signed-out account visible at all (UsageBar/Core/KnownAccounts.swift), then runs it. All four
# are Foundation-only, so nothing else comes along; no Xcode test target needed. Exits non-zero on
# failure.
#
# The probe is driven against stub CLIs the harness writes itself, never this machine's real
# accounts: `claude auth status` and `codex login status` are read-only, but a test whose answer
# depends on who happens to be signed in right now passes for reasons unrelated to the code.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -o "$out" tests/logincheck/main.swift \
  UsageBar/Core/LoginStatusCommand.swift UsageBar/Core/RenewLoginCommand.swift UsageBar/Core/CLIRunner.swift UsageBar/Core/CLISearchPath.swift UsageBar/Core/ClaudeStableExecutable.swift \
  UsageBar/Core/LoginProbeGate.swift \
  UsageBar/Core/KnownAccounts.swift UsageBar/Providers/ProviderModels.swift \
  UsageBar/Core/AccountRowCarry.swift
"$out"
