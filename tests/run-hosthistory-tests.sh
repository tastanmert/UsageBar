#!/bin/bash
# Compiles the load history's pieces (UsageBar/Core/HostLoadHistory.swift, the line format and its
# reader; HostLoadStats.swift, the rates; HostLoadHistoryWriter.swift, the app's writer;
# UsageBarCLI/HostHistoryCommand.swift, `usagebar status --history`) with an assertion harness and runs
# it. The command's default gate comes from HostHealthLogic.swift, which brings its two neighbours.
# Only Foundation and Darwin, so no Xcode target is needed; exits non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -o "$out" tests/hosthistory/main.swift \
  UsageBar/Core/HostLoadHistory.swift UsageBar/Core/HostLoadStats.swift UsageBar/Core/HostLoadHistoryWriter.swift \
  UsageBarCLI/HostHistoryCommand.swift \
  UsageBar/Core/HostHealthLogic.swift UsageBar/Core/HostHealthCPU.swift UsageBar/Core/HostHealthNaming.swift UsageBar/Core/HostHealthSessions.swift \
  UsageBar/Core/KeystrokeText.swift
"$out"
