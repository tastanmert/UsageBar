#!/bin/bash
# Compiles the usage panel's width arithmetic (UsageBar/Core/PanelGeometry.swift) with a small
# assertion harness and runs it. CoreGraphics only, so no AppKit and no Xcode test target; the
# surfaces apply this arithmetic through PopoverRootView.popoverWidth / columnCount.
# Exits non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc -o "$out" tests/panelwidth/main.swift tests/panelwidth/meterchecks.swift UsageBar/Core/PanelGeometry.swift UsageBar/Core/MeterColumns.swift
"$out"
