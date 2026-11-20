#!/bin/bash
# UsageBar Phase 1: the CLI's read-only gate (UsageBarCLI/BrimCLIGate.swift).
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift UsageBarCLI/BrimCLIGate.swift tests/brimcligate/main.swift -o "$out"
"$out"
