#!/bin/bash
# Compiles the leftovers-about-to-reset alert (UsageBar/Core/ClearanceIdleAlert.swift) with the cycle
# keys it dedups on and the clearance rule it reads, with a small assertion harness, and runs it.
# All three files are Foundation-only; no Xcode test target needed. Exits non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc -o "$out" tests/clearanceidle/main.swift UsageBar/Core/ClearanceIdleAlert.swift \
    UsageBar/Core/DryPoolLogic.swift UsageBarCLI/AccountComfort.swift
"$out"
