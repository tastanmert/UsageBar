#!/bin/bash
# Compiles account discovery's home listing (UsageBar/Core/AccountHomeListing.swift) with a small
# assertion harness and runs it against a fake home whose Downloads, Desktop and Documents are mode
# 000. Pins discovery and the watcher roots must never touch those three.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc -o "$out" tests/homelisting/main.swift UsageBar/Core/AccountHomeListing.swift
"$out"
