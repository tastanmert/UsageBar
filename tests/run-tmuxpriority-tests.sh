#!/bin/bash
# Compiles the tmux priority guard's rules and reader (UsageBar/Core/TmuxPriority{Logic,Readers}.swift,
# Foundation and Darwin only) with an assertion harness and runs it. The ProcessTree set comes
# along for `ProcessTree.displayName(forPath:)`, the program naming the guard reuses. Read-only:
# the harness asks `ps` about this process's parent and about any tmux server of the current
# user, and starts and signals nothing.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -o "$out" tests/tmuxpriority/main.swift \
  UsageBar/Core/TmuxPriorityLogic.swift UsageBar/Core/TmuxPriorityReaders.swift \
  UsageBar/Core/ProcessTreeStats.swift UsageBar/Core/ProcessTreePool.swift UsageBar/Core/ProcessTreeRates.swift UsageBar/Core/ProcessTreeLine.swift \
  UsageBar/Core/FootprintAlerts.swift UsageBar/Core/PickContract.swift
"$out"
