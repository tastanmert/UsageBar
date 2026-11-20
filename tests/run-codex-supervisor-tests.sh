#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
# CodexWaitEvents.swift is the Codex wait-event adapter under test; SessionWaitEvent.swift and
# SessionWaitLogic.swift are the shared contract it builds on, and UserNotice.swift and
# OpenTurn.swift are what SessionWaitLogic.swift needs to compile (support.swift stands in for
# the one Snapshot.swift symbol OpenTurn.swift would otherwise drag in).
swiftc UsageBar/Core/BrandPaths.swift -o "$out/run" tests/codex-supervisor/main.swift tests/codex-supervisor/waitchecks.swift tests/codex-supervisor/waitquestionchecks.swift \
  tests/codex-supervisor/updatechecks.swift tests/codex-supervisor/startupchecks.swift \
  tests/codex-supervisor/startupchoicechecks.swift tests/codex-supervisor/startuptrustchecks.swift \
  tests/codex-supervisor/updatecommandchecks.swift tests/codex-supervisor/handoffchecks.swift tests/codex-supervisor/wallchecks.swift \
  tests/codex-supervisor/support.swift \
  UsageBar/Core/SessionMonitoring.swift UsageBar/Core/CodexSessionHooks.swift UsageBar/Core/ProjectStatusLine.swift \
  UsageBarCLI/CodexSessionEvents.swift UsageBarCLI/CodexSessionContext.swift \
  UsageBarCLI/SessionState.swift UsageBarCLI/CodexStartupScreenRecord.swift UsageBarCLI/ReloadRequest.swift \
  UsageBarCLI/CodexWaitEvents.swift UsageBarCLI/SessionWaitEvent.swift UsageBarCLI/SessionWaitLogic.swift \
  UsageBarCLI/UserNotice.swift UsageBarCLI/OpenTurn.swift \
  UsageBarCLI/CodexUpdateDecision.swift UsageBarCLI/CodexStartupScreen.swift UsageBarCLI/CodexStartupChoice.swift \
  UsageBarCLI/CodexHandoff.swift
"$out/run"
