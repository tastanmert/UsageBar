#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
swiftc -o "$work/run" tests/fixalock/main.swift tests/fixalock/stubs.swift \
  UsageBar/Core/BrandPaths.swift UsageBarCLI/BrimCLIGate.swift \
  UsageBar/Providers/ProviderModels.swift UsageBar/Providers/Codex/CodexAppServerClient.swift \
  UsageBar/Providers/Codex/CodexConsume.swift UsageBar/Providers/Codex/CodexIdentity.swift \
  UsageBar/Providers/Codex/CodexResetBank.swift UsageBar/Providers/Codex/CodexReadFailure.swift \
  UsageBar/Core/BrimCodexReset.swift UsageBar/Core/BrimPanelModel.swift UsageBar/Core/UsageSnapshot.swift
"$work/run"
