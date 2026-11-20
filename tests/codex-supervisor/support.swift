import Foundation

// A TEST-ONLY STAND-IN, never part of the app, mirroring `tests/waitevents/support.swift` for the
// same reason: `UsageBarCLI/SessionWaitLogic.swift` (which `CodexWaitTracker` builds on) needs
// `userQuestionTools` from `UsageBarCLI/OpenTurn.swift`, and OpenTurn.swift's own `openToolCall(inTail:)`,
// which nothing here calls, needs `parseISO` from `UsageBarCLI/Snapshot.swift`, whose compile closure
// is the whole quota/account read. This gives the symbol the same signature so OpenTurn.swift
// compiles; no assertion in this suite depends on its behaviour.
func parseISO(_ string: String) -> Date? {
    ISO8601DateFormatter().date(from: string)
}
