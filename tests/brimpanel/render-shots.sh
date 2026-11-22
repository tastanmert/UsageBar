#!/bin/bash
# Renders the UsageBar panel and glyph from fixtures into PNGs (default .brimbar-work/phase2-shots).
# A visual check, not a suite: the name keeps it out of run-all-tests.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
awk '/^\/\/\/ Like `ProviderIconShape`/ {exit} {print}' UsageBar/Views/ProviderIconShape.swift > "$work/ProviderShape.swift"
swiftc "$work/ProviderShape.swift" UsageBar/Providers/ProviderMarks.swift UsageBar/Core/ProviderBrand.swift UsageBar/Stores/DisplaySettings.swift -Xfrontend -disable-sandbox -o "$work/render" UsageBar/Core/BrandPaths.swift UsageBar/Core/UsageSnapshot.swift \
  UsageBar/Providers/ProviderModels.swift UsageBar/Core/BrimPanelModel.swift UsageBar/Core/BrimPanelLayout.swift UsageBar/Core/BrimSettingsModel.swift UsageBar/Core/SubscriptionRenewal.swift UsageBar/Views/BrimGlyph.swift \
  UsageBar/MenuBar/BrimStatusMenu.swift UsageBar/Views/BrimPanelView.swift UsageBar/Views/BrimPanelParts.swift tests/brimpanel/fixtures.swift tests/brimpanel/render/main.swift
[ -x "$work/render" ] || { echo "render tool did not build" >&2; exit 1; }
# The catalog's Turkish, for the tr-dark shots.
xcrun xcstringstool compile UsageBar/Resources/Localizable.xcstrings --output-directory "$work/strings" >/dev/null
"$work/render" "${1:-.brimbar-work/phase2-shots}" "${@:2}" --strings "$work/strings"
