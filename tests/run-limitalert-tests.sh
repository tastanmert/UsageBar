#!/bin/bash
# Compiles the per-account limit alerts' pure logic (UsageBar/Core/LimitAlertLogic.swift) with the
# cycle rule it borrows (DryPoolLogic.swift) and an assertion harness, and runs it.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc -o "$out" tests/limitalert/main.swift UsageBar/Core/LimitAlertLogic.swift UsageBar/Core/DryPoolLogic.swift
"$out"
