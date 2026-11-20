#!/bin/bash
# Compiles the one-answer-per-directory git gate (gitDirectoryFacts in UsageBarCLI/GitRepoRoot.swift)
# with its assertion harness and runs it. GitRepoRoot.swift is Foundation-only, so no Xcode target
# is needed; exits non-zero on failure. Real git in a temp directory: how many subprocesses a
# roster of sessions costs, and that the answers equal the old per-call ones, are both facts about
# git rather than about our idea of it. Nothing here touches the real ~/.usagebar (the disk layer is
# off unless a test points it at a temp file).
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -o "$out" tests/gitfacts/main.swift UsageBarCLI/GitRepoRoot.swift
"$out"
