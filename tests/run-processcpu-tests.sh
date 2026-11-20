#!/bin/bash
# Compiles the one-process CPU watch's pure half (ProcessCPUWatchLogic) and its ps reader with an
# assertion harness and runs it. Logic reaches hostHealthIsSystemPath, so the host-health sources
# come with it (the list tests/run-hosthealth-tests.sh builds). Foundation only, no Xcode target;
# exits non-zero on failure. The end of the harness reads the monitor, timer and catalog as text
# for the structural promises a pure harness cannot drive.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -o "$out" tests/processcpu/main.swift \
  UsageBar/Core/ProcessCPUWatchLogic.swift UsageBar/Core/ProcessCPUWatchReaders.swift \
  UsageBar/Core/HostHealthLogic.swift UsageBar/Core/HostHealthCPU.swift UsageBar/Core/HostHealthStatus.swift UsageBar/Core/HostHealthNaming.swift UsageBar/Core/HostHealthSessions.swift \
  UsageBar/Core/KeystrokeText.swift UsageBarCLI/HostHealthKnockLogic.swift
"$out"
