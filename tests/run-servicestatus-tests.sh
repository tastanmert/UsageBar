#!/bin/bash
# Compiles the status-page parse and announcement rule (UsageBar/Core/ServiceStatusLogic.swift)
# with an assertion harness and runs it. No network.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc -o "$out" tests/servicestatus/main.swift UsageBar/Core/ServiceStatusLogic.swift
"$out"
