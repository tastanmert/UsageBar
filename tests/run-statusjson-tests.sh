#!/bin/bash
# Compiles the CLI's `status --json` contract (UsageBarCLI/Snapshot.swift) together with a small
# assertion harness. ResumePrompt comes with Snapshot.swift, whose unsupervised launcher asks it
# what to hand the exec'd child (`resumePromptSuppression`).
# assertion harness and runs it. No Xcode test target needed; exits non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -o "$out" tests/statusjson/main.swift tests/statusjson/resetpassedchecks.swift tests/statusjson/capweightchecks.swift tests/statusjson/machinechecks.swift \
  tests/statusjson/clearancemarkerchecks.swift tests/statusjson/pinstepasidechecks.swift tests/statusjson/sharedloginchecks.swift UsageBarCLI/Snapshot.swift UsageBar/Core/ClaudeStableExecutable.swift \
  UsageBarCLI/CodexLaunchArgs.swift UsageBarCLI/AccountPick.swift UsageBarCLI/AccountPick+Handoff.swift \
  UsageBarCLI/AccountBinding.swift UsageBarCLI/AccountReserveReader.swift UsageBar/Core/AccountReserve.swift \
  UsageBarCLI/ProviderExecutable.swift UsageBarCLI/StatusReport.swift UsageBarCLI/CodexStartupScreenRecord.swift UsageBarCLI/StatusResetText.swift UsageBar/Core/HeldOverReset.swift \
  UsageBarCLI/ResumePrompt.swift \
    UsageBarCLI/UsageAdvisor.swift UsageBarCLI/UsageAdvisorMath.swift UsageBarCLI/AccountComfort.swift
"$out"
