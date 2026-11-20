#!/bin/bash
# Compiles the move-to-Applications decision layer (UsageBar/Core/InstallLocation.swift) and its file
# mover (UsageBar/Core/AppMover.swift) with an assertion harness and runs it. The mover is exercised on
# throwaway bundles in a temporary directory; nothing here writes to /Applications or the Trash.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc -target "$(uname -m)-apple-macos14.0" -o "$out" tests/movetoapps/main.swift \
  UsageBar/Core/InstallLocation.swift UsageBar/Core/AppMover.swift UsageBar/Core/CaptureLaunch.swift
"$out"
