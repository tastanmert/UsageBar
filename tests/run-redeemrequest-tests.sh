#!/bin/bash
# Compiles the `usagebar redeem` request channel (UsageBarCLI/RedeemRequest.swift, Foundation-only) with a
# small assertion harness and runs it. No credit is ever spent. Exits non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -o "$out" tests/redeemrequest/main.swift UsageBarCLI/RedeemRequest.swift
"$out"
