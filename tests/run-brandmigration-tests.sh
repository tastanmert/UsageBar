#!/bin/bash
# The BrimBar -> UsageBar carry-over against a scratch home and a scratch defaults domain.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
swiftc -o "$work/run" tests/brandmigration/main.swift \
  UsageBar/Core/LegacyBrandMigration.swift UsageBar/Core/BrandPaths.swift UsageBar/Core/AccountHomeListing.swift
"$work/run"
