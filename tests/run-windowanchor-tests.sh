#!/bin/bash
# Compiles the resize anchor's pure geometry (UsageBar/Core/ResizeAnchor.swift) with a small assertion
# harness and runs it. No Xcode test target; the window controllers apply this arithmetic through
# NSWindow.setFrameOrigin (WindowPlacement.swift), whose content anchor content.swift checks on
# real, never-shown AppKit windows.
# Exits non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc -o "$out" tests/windowanchor/main.swift tests/windowanchor/popover.swift \
    tests/windowanchor/summon.swift tests/windowanchor/content.swift tests/windowanchor/level.swift \
    UsageBar/Core/WindowPlacement.swift UsageBar/Core/ResizeAnchor.swift UsageBar/Core/ViewOptionsCardPlacement.swift \
    UsageBar/Core/StatusAnchor.swift UsageBar/Core/TogglePress.swift UsageBar/Core/PanelPinLevel.swift
"$out"
