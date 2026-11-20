#!/bin/bash
# Compiles the redeem propagation window logic (UsageBar/Core/RedeemPropagation.swift) and the
# four-state reset offer (UsageBar/Core/ResetOffer.swift, with the types it reads) with a small
# assertion harness and runs it. The file is Foundation-only, so nothing else comes along; no
# Xcode test target needed. Exits non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -o "$out" tests/redeem/main.swift tests/redeem/offerchecks.swift tests/redeem/listparitychecks.swift \
  UsageBar/Core/RedeemPropagation.swift UsageBar/Core/ResetOffer.swift UsageBar/Core/LimitReset.swift \
  UsageBar/Providers/ProviderModels.swift
"$out"
