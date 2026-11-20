#!/bin/bash
# Compiles the token activity heatmap's arithmetic (UsageBar/Core/TokenStats/TokenActivityHeatmap.swift,
# which calls the Rust core through the UniFFI bindings) together with a small assertion harness and
# runs it. No Xcode test target needed; exits non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET=14.0
(cd rust && cargo build --quiet --release --locked -p usagebar_ffi)
out=$(mktemp -d)/run
swiftc -I rust/include -L rust/target/release -o "$out" tests/tokenheatmap/main.swift \
  UsageBar/Core/TokenStats/TokenActivityHeatmap.swift rust/generated/swift/usagebar_ffi.swift
"$out"
