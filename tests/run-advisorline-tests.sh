#!/bin/bash
# Compiles the advisor row's conclusion logic (UsageBar/Core/AdvisorConclusion.swift) with the usage
# advisor's pure math it reads the verdict from, plus a small assertion harness, and runs it.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc -o "$out" tests/advisorline/main.swift UsageBar/Core/AdvisorConclusion.swift \
  UsageBarCLI/UsageAdvisor.swift UsageBarCLI/UsageAdvisorMath.swift
"$out"
