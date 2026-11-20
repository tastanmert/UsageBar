#!/bin/bash
# The token statistics' Rust core (rust/crates/core/src/tokenstats) and the Swift shells over it
# (UsageBar/Core/TokenStats): the Rust unit tests, the freshness of the committed UniFFI bindings,
# then tests/tokenstats/main.swift compiled with the bindings and the core linked (day arithmetic
# against the core across zones, a whole scan through the bindings, the Swift String rules).
# Count assertions with `command grep -c '^PASS:'`.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET=14.0
(cd rust && cargo test --quiet --locked -p usagebar_core tokenstats && cargo test --quiet --locked -p usagebar_sys)
scripts/gen-uniffi.sh --check
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -I rust/include -L rust/target/release -o "$out" tests/tokenstats/main.swift \
  UsageBar/Core/TokenStats/TokenTotals.swift UsageBar/Core/TokenStats/AppTokenStatsHost.swift \
  UsageBar/Core/TokenStats/TokenActivityHeatmap.swift UsageBar/Core/WorktreeOrigins.swift \
  rust/generated/swift/usagebar_ffi.swift
"$out"
