#!/bin/bash
# Compiles the hover callout's placement geometry (UsageBar/Core/TooltipPlacement.swift) with a small
# assertion harness and runs it. CoreGraphics only, so no SwiftUI and no Xcode test target; the
# callout applies this arithmetic through two alignment guides (see UsageBar/Views/UsageBarTooltip.swift).
# Exits non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc -o "$out" tests/tooltip/main.swift UsageBar/Core/TooltipPlacement.swift
"$out"
