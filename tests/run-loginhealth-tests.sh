#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
login_health_build=$(mktemp -d)
trap 'rm -rf "$login_health_build"' EXIT
swiftc UsageBar/Core/BrandPaths.swift -warnings-as-errors -o "$login_health_build/run" \
  tests/loginhealth/main.swift UsageBar/Core/LoginHealthAlerts.swift UsageBar/Core/LoginUsageHealth.swift \
  UsageBar/Core/ClaudeLoginExpiry.swift UsageBar/Core/ClaudeLoginExpiryKeychain.swift \
  UsageBar/Core/Keychain/ClaudeKeychainService.swift UsageBar/Core/Keychain/KeychainReader.swift \
  UsageBar/Providers/Claude/ClaudeUsageCLI.swift UsageBar/Core/CLIRunner.swift UsageBar/Core/CLISearchPath.swift UsageBar/Core/ClaudeStableExecutable.swift \
  UsageBar/Core/LoginStatusCommand.swift UsageBar/Core/RenewLoginCommand.swift UsageBar/Core/LoginProbeGate.swift \
  UsageBar/Providers/ProviderModels.swift
"$login_health_build/run"
swiftc UsageBar/Core/BrandPaths.swift -warnings-as-errors -target "$(uname -m)-apple-macos14.0" -o "$login_health_build/store" \
  tests/loginhealth/storechecks.swift tests/loginhealth/storestubs.swift tests/loginhealth/storerounds.swift \
  UsageBar/Stores/LoginStatusStore.swift UsageBar/Core/LoginUsageHealth.swift \
  UsageBar/Core/LoginStatusCommand.swift UsageBar/Core/LoginProbeGate.swift UsageBar/Core/AccountIdentity.swift \
  UsageBar/Core/RenewLoginCommand.swift UsageBar/Core/CLIRunner.swift UsageBar/Core/CLISearchPath.swift UsageBar/Core/ClaudeStableExecutable.swift UsageBar/Providers/ProviderModels.swift
"$login_health_build/store"
