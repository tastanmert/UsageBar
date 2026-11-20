#!/bin/bash
# Always-on gates, confirmed Claude reset claims through a fake transport, and panel formatting.
# No app, network, Keychain or preferences written.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
swiftc -o "$work/run" tests/brimlive/main.swift \
    UsageBar/Core/BrandPaths.swift UsageBarCLI/BrimCLIGate.swift \
    UsageBar/Core/ClaudeResetInventory.swift UsageBar/Core/ClaudeResetInventoryFetch.swift \
    UsageBar/Core/ClaudeResetClaim.swift UsageBar/Core/ClaudeResetClaimGate.swift UsageBar/Core/BrimClaudeClaim.swift \
    UsageBar/Core/BrimClaudeResetSchedule.swift UsageBar/Core/BrimPanelModel.swift UsageBar/Core/ClaudeStatePath.swift \
    UsageBar/Core/UsageSnapshot.swift UsageBar/Providers/ProviderModels.swift \
    UsageBar/Core/ClaudeLoginExpiry.swift UsageBar/Core/ClaudeLoginExpiryKeychain.swift \
    UsageBar/Core/Keychain/ClaudeKeychainService.swift UsageBar/Core/Keychain/KeychainReader.swift
"$work/run"
