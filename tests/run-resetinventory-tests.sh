#!/bin/bash
# Claude limit-reset inventory, read path only: parser, kind rule, credential handling (expired:
# nothing sent), request shape, the 10 minute schedule with its back-offs, and unknown versus zero
# in the panel model. No network and no Keychain: every credential read and transport is injected.
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
swiftc -o "$build_dir/run" \
    tests/resetinventory/main.swift \
    UsageBar/Core/ClaudeResetInventory.swift UsageBar/Core/ClaudeResetInventoryFetch.swift \
    UsageBar/Core/BrimClaudeResetSchedule.swift UsageBar/Core/BrimPanelModel.swift \
    UsageBar/Core/UsageSnapshot.swift UsageBar/Providers/ProviderModels.swift UsageBar/Core/BrandPaths.swift \
    UsageBar/Core/ClaudeLoginExpiry.swift UsageBar/Core/ClaudeLoginExpiryKeychain.swift \
    UsageBar/Core/Keychain/ClaudeKeychainService.swift UsageBar/Core/Keychain/KeychainReader.swift
"$build_dir/run"
