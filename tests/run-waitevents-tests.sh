#!/bin/bash
# Compiles the session-wait-event contract (UsageBarCLI/SessionWaitEvent.swift,
# UsageBarCLI/SessionWaitLogic.swift, UsageBarCLI/SessionWaitSpool.swift, UsageBarCLI/EventDelivery.swift,
# UsageBarCLI/EventsCommand.swift) together with a small assertion harness and runs it. No Xcode target
# is needed; exits non-zero on failure.
#
# The source list is that contract's closure and nothing more. SessionState.swift and
# UserNotice.swift bring the `UserWait`/`UserNotice` types the pure functions are built on;
# ReloadRequest.swift comes along because both of those default their directory argument to
# `supervisorStateDir`, which lives there; ReloadRequest.swift in turn needs
# UsageBar/Core/SessionMonitoring.swift (the live-session registry its reload-readiness check reads),
# which is otherwise self-contained. OpenTurn.swift brings `userQuestionTools`, the one lookup
# `openWaitRequest`'s question row needs and the only thing pulled in from outside the plan's own
# minimal list (docs/plans/[WIP] feature-session-wait-events.md §12), but OpenTurn.swift's OWN
# `openToolCall(inTail:)`, a function nothing here calls, needs `parseISO` (UsageBarCLI/Snapshot.swift),
# which pulls in that file's entire ~14-file quota/account closure. `tests/waitevents/support.swift`
# stands in for `parseISO` alone rather than pay that, and says why in its own header.
# EventDelivery.swift and EventsCommand.swift (§12 T11-T13, package P4) need nothing beyond what is
# already in this closure: CryptoKit and Foundation only.
# EventsFollow.swift (`usagebar events --follow`) needs Darwin kqueue only.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -o "$out" tests/waitevents/main.swift tests/waitevents/support.swift \
  tests/waitevents/loopbackreceiver.swift tests/waitevents/deliveryhandoffchecks.swift \
  tests/waitevents/deliverycontractchecks.swift tests/waitevents/followchecks.swift \
  UsageBarCLI/SessionWaitEvent.swift UsageBarCLI/SessionWaitLogic.swift UsageBarCLI/SessionWaitSpool.swift \
  UsageBarCLI/EventDelivery.swift UsageBarCLI/EventsCommand.swift UsageBarCLI/EventsFollow.swift \
  UsageBarCLI/SessionState.swift UsageBarCLI/CodexStartupScreenRecord.swift UsageBarCLI/UserNotice.swift UsageBarCLI/ReloadRequest.swift \
  UsageBarCLI/OpenTurn.swift UsageBar/Core/SessionMonitoring.swift UsageBarCLI/EventDeliverySpawn.swift
"$out"
