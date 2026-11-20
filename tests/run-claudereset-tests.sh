#!/bin/bash
# Compiles the Claude usage-text mapper (reset-time year inference) with a small assertion
# harness and runs it. No Xcode test target needed; exits non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -o "$out" tests/claudereset/main.swift \
  UsageBar/Providers/Claude/ClaudeUsageCLI.swift UsageBar/Core/CLIRunner.swift UsageBar/Core/CLISearchPath.swift UsageBar/Core/ClaudeStableExecutable.swift \
  UsageBar/Providers/ProviderModels.swift
"$out"
