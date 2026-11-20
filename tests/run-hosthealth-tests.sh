#!/bin/bash
# Compiles the host-health watch's pure halves (UsageBar/Core/HostHealthLogic.swift, the state machine
# and the report both targets read, HostHealthNaming.swift, who an alarm that is still on names next,
# and UsageBarCLI/HostHealthKnockLogic.swift, what the supervisor's station decides) together with an
# assertion harness, and runs it. KeystrokeText.swift comes with them: the sentence a session is
# told repairs the process names in it through that one rule. All of them depend only on Foundation,
# so no Xcode target is needed; exits non-zero on failure.
#
# The harness is three files, the division tests/supervisor keeps: main.swift holds the fixtures,
# `expect` and the usagebar, knockchecks.swift holds the knock's own half (split on size, 2026-09-05)
# and namingchecks.swift the alarm that is still on and the one a restart resumes (B-2238).
#
# The suite also reads this feature's sources as text at the end. Those assertions are the
# structural promises this feature was accepted under - no timer of its own, no subprocess, two
# syscalls on the ordinary sample, the process-table walk confined to the branch that has just
# raised an alarm (measured between that branch's own braces, not from where it opens), and the
# station speaking last through the knock's existing door - and not one of them can be driven from a
# harness: they need a running timer, a live session and a machine actually in trouble.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -o "$out" tests/hosthealth/main.swift tests/hosthealth/knockchecks.swift tests/hosthealth/namingchecks.swift \
  tests/hosthealth/cpuchecks.swift tests/hosthealth/queuechecks.swift \
  UsageBar/Core/HostHealthLogic.swift UsageBar/Core/HostHealthCPU.swift UsageBar/Core/HostHealthStatus.swift UsageBar/Core/HostHealthNaming.swift UsageBar/Core/HostHealthSessions.swift \
  UsageBar/Core/KeystrokeText.swift UsageBarCLI/HostHealthKnockLogic.swift
"$out"
