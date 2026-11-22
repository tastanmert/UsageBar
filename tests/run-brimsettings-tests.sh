#!/bin/bash
# UsageBar settings model against fixtures and a pretend disk; no app, no user data.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift UsageBar/Core/UsageSnapshot.swift UsageBar/Providers/ProviderModels.swift \
  UsageBar/Core/BrimPanelModel.swift UsageBar/Core/BrimPanelLayout.swift UsageBar/Core/BrimSettingsModel.swift UsageBar/Core/SubscriptionRenewal.swift UsageBar/Core/TokenStats/UsageBreakdown.swift tests/brimpanel/fixtures.swift \
  tests/brimsettings/disk.swift tests/brimsettings/main.swift -o "$out"
"$out"
