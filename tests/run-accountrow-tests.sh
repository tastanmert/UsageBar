#!/bin/bash
# Compiles the rules the Settings account list runs on - a row's login state
# (UsageBar/Core/AccountSignIn.swift), a row's identity (UsageBar/Core/AccountIdentity.swift), and what
# the list itself says when it holds no rows (UsageBar/Core/AccountListState.swift) - with a small
# assertion harness and runs it. All three are Foundation-only, so nothing else comes along; no
# Xcode test target needed. Exits non-zero on failure.
#
# The last suite also reads two sources as text (the store that reports the discovery pass, the
# pane that asks about it): neither end can be compiled in here, and the rule is only worth having
# if both are really wired to it. Run from the repo root, which the cd below guarantees.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc -o "$out" tests/accountrow/main.swift tests/accountrow/accountrowchecks.swift \
  UsageBar/Core/AccountSignIn.swift UsageBar/Core/AccountIdentity.swift \
  UsageBar/Core/AccountListState.swift UsageBar/Core/ReorderGeometry.swift \
  UsageBar/Core/AccountReserve.swift UsageBar/Core/ReserveStrip.swift \
  UsageBar/Core/HarnessSharing.swift UsageBar/Core/PathIdentity.swift \
  UsageBar/Providers/ProviderModels.swift
"$out"
