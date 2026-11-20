#!/bin/bash
# Compiles UsageHistory (the incremental history.jsonl read cache) with an assertion harness that
# compares every read against a whole-file reference decode. Exits non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -o "$out" tests/usagehistory/main.swift UsageBar/Core/UsageHistory.swift \
    UsageBar/Providers/ProviderModels.swift UsageBar/Stores/DisplaySettings.swift
"$out"
