#!/bin/bash
# Renders the UsageBar settings tabs from fixtures into PNGs (default .brimbar-work/settings-shots),
# light and dark, English and Turkish. A visual check, not a suite: the name keeps it out of
# run-all-tests.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
awk '/^\/\/\/ Like `ProviderIconShape`/ {exit} {print}' UsageBar/Views/ProviderIconShape.swift > "$work/ProviderShape.swift"
swiftc -Xfrontend -disable-sandbox "$work/ProviderShape.swift" UsageBar/Providers/ProviderMarks.swift UsageBar/Core/ProviderBrand.swift UsageBar/Stores/DisplaySettings.swift -o "$work/render" UsageBar/Core/BrandPaths.swift UsageBar/Core/UsageSnapshot.swift \
  UsageBar/Providers/ProviderModels.swift UsageBar/Core/BrimPanelModel.swift UsageBar/Core/BrimPanelLayout.swift UsageBar/Core/BrimSettingsModel.swift UsageBar/Core/SubscriptionRenewal.swift \
  UsageBar/Views/BrimGlyph.swift UsageBar/Views/BrimSettingsParts.swift UsageBar/Views/BrimPanelParts.swift UsageBar/Views/BrimSettingsPanes.swift \
  UsageBar/Views/BrimSettingsTables.swift tests/brimpanel/fixtures.swift tests/brimsettings/disk.swift \
  tests/brimsettings/render/main.swift
[ -x "$work/render" ] || { echo "render tool did not build" >&2; exit 1; }
"$work/render" "${1:-.brimbar-work/settings-shots}" "${@:2}"
