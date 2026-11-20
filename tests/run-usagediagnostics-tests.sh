#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for variant in debug release; do
    flags=(-O)
    if [ "$variant" = debug ]; then flags=(-D DEBUG); fi
    swiftc "${flags[@]}" UsageBar/Core/BrandPaths.swift UsageBar/Core/BrimUsageDiagnostics.swift \
        tests/usagediagnostics/main.swift -o "$work/$variant"
    "$work/$variant"
done
