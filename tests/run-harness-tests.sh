#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
swiftc UsageBar/Core/BrandPaths.swift UsageBar/Core/LegacyIdentifierMigration.swift -swift-version 6 -strict-concurrency=complete UsageBar/Core/Harness/*.swift UsageBarCLI/HarnessCommand.swift UsageBarCLI/HarnessToolsCommand.swift UsageBarCLI/CodexHookCommand.swift \
    UsageBarCLI/InboxCommand.swift tests/harness/main.swift -o "$work/usagebar"
USAGEBAR_HARNESS_TEST_BINARY="$work/usagebar" python3 -m unittest discover -s tests/harness -p '*checks.py' -v
