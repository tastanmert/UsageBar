#!/bin/bash
# Source-text checks that the panel's and the menu bar's per-redraw waste stays gone (reported
# as app hangs in the field). Exits non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc -o "$out" tests/renderwaste/main.swift
"$out"
