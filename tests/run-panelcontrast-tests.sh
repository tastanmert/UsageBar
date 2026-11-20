#!/bin/bash
# The Detailed panel's text contrast on the worst desktop (UsageBar/Core/PanelPalette.swift), a pure
# arithmetic harness: Foundation only, no AppKit and no Xcode test target. Exits non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc -o "$out" tests/panelcontrast/main.swift UsageBar/Core/PanelPalette.swift UsageBar/Core/PanelMetrics.swift UsageBar/Core/PanelGeometry.swift
"$out"
