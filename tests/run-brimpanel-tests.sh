#!/bin/bash
# UsageBar panel model against UsageBar snapshot fixtures; no app, no user data.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift UsageBar/Core/UsageSnapshot.swift UsageBar/Providers/ProviderModels.swift \
  UsageBar/Core/BrimPanelModel.swift UsageBar/Core/BrimPanelLayout.swift UsageBar/Core/BrimSettingsModel.swift UsageBar/Core/SubscriptionRenewal.swift tests/brimpanel/fixtures.swift tests/brimpanel/main.swift -o "$out"
"$out"
