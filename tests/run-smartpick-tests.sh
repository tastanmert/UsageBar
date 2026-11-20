#!/bin/bash
# Compiles the CLI's burn-rate account pick (UsageBarCLI/AccountPick.swift) together with a small
# assertion harness and runs it. No Xcode test target needed; exits non-zero on failure.
#
# Three harness files: main.swift is the scoring and the picks built on it, launchchecks.swift is the
# plumbing a launch runs through once an account is chosen (start-mode injection, resolving a manual
# pin), reservechecks.swift the personal account's reserve - the state file it is read from and the
# one subtraction it becomes. Split for file size, and the seams are "which account" versus
# "launched how" versus "how much of it is UsageBar's to spend". loadchecks.swift is the load gate
#: a thin account already carrying two live sessions takes no new one, nor a moved
# one, while a sibling can. sharedloginchecks.swift is two config homes on one Claude login
#: the duplicate is never a target, and its sessions count on the kept account.
#
# ResumePrompt is in the source list because the unsupervised launcher in Snapshot.swift asks it
# what to hand the exec'd child (`resumePromptSuppression`).
#
# LaunchResume/LastConversation are which CONVERSATION a launch picks up, which is the other half of
# the start mode: the injection in Snapshot.swift is now `--resume <id>` and those two decide the id.
# OpenTurn comes with them for `transcriptTail` (the half of a transcript read they share with the
# supervisor) and TranscriptSignals for the two smallest readings on that track, a line's timestamp
# and whether a string can name a transcript at all. None of them reaches the supervisor, which is
# what keeps this suite compiling a launch rather than a fleet.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)/run
swiftc UsageBar/Core/BrandPaths.swift -o "$out" tests/smartpick/main.swift tests/smartpick/launchchecks.swift \
  tests/smartpick/conversationchecks.swift tests/smartpick/reservechecks.swift \
  tests/smartpick/codexstartchecks.swift tests/smartpick/comfortchecks.swift tests/smartpick/clearancechecks.swift \
  tests/smartpick/loadchecks.swift tests/smartpick/sharedloginchecks.swift tests/smartpick/tiebreakchecks.swift \
  UsageBarCLI/CodexStartMode.swift \
  UsageBarCLI/Snapshot.swift UsageBar/Core/ClaudeStableExecutable.swift UsageBarCLI/CodexLaunchArgs.swift UsageBarCLI/AccountPick.swift UsageBarCLI/AccountPick+Handoff.swift \
  UsageBarCLI/LaunchResume.swift UsageBarCLI/LastConversation.swift \
  UsageBarCLI/OpenTurn.swift UsageBarCLI/TranscriptSignals.swift \
  UsageBarCLI/AccountBinding.swift UsageBarCLI/AccountReserveReader.swift UsageBar/Core/AccountReserve.swift \
  UsageBarCLI/ResumePrompt.swift \
  UsageBarCLI/ProviderExecutable.swift UsageBarCLI/AccountComfort.swift
"$out"
