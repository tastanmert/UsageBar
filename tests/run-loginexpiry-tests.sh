#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
swiftc UsageBar/Core/BrandPaths.swift -warnings-as-errors -o "$build_dir/run" \
    tests/loginexpiry/main.swift \
    UsageBar/Core/ClaudeLoginExpiry.swift UsageBar/Core/ClaudeLoginExpiryKeychain.swift \
    UsageBar/Core/Keychain/ClaudeKeychainService.swift UsageBar/Core/Keychain/KeychainReader.swift
"$build_dir/run"
