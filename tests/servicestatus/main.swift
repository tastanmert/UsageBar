import Foundation

// Assertion harness for ServiceStatusLogic (compiled with UsageBar/Core/ServiceStatusLogic.swift).

var failures = 0
func expect(_ condition: Bool, _ name: String) {
    if condition { print("PASS \(name)") } else { failures += 1; print("FAIL \(name)") }
}

let now = Date(timeIntervalSince1970: 1_800_000_000)
func doc(_ indicator: String, _ text: String = "x") -> Data {
    Data(#"{"page":{"id":"p","name":"Claude"},"status":{"indicator":"\#(indicator)","description":"\#(text)"}}"#.utf8)
}

// 1. Parse: the two shapes the pages serve, an unknown indicator, and garbage.
do {
    let minor = ServiceStatusLogic.parse(doc("minor", "Partially Degraded Service"), now: now)
    expect(minor?.indicator == .minor && minor?.description == "Partially Degraded Service", "parses minor")
    expect(ServiceStatusLogic.parse(doc("none"), now: now)?.indicator == ServiceStatusLogic.Indicator.none,
           "parses none")
    expect(ServiceStatusLogic.parse(doc("elevated"), now: now)?.indicator == .minor, "unknown indicator is an incident")
    expect(ServiceStatusLogic.parse(Data("<html>".utf8), now: now) == nil, "a non-document is no reading")
    expect(ServiceStatusLogic.parse(Data(#"{"page":{}}"#.utf8), now: now) == nil, "a document without status is no reading")
}

// 2. Shown: incidents only, and only while fresh.
do {
    let incident = ServiceStatusLogic.Reading(indicator: .major, description: "", readAt: now)
    expect(ServiceStatusLogic.shown(incident, now: now) != nil, "fresh incident is shown")
    expect(ServiceStatusLogic.shown(incident, now: now.addingTimeInterval(31 * 60)) == nil, "old reading is hidden")
    let fine = ServiceStatusLogic.Reading(indicator: .none, description: "", readAt: now)
    expect(ServiceStatusLogic.shown(fine, now: now) == nil, "operational is not shown")
    expect(ServiceStatusLogic.shown(nil, now: now) == nil, "no reading is not shown")
}

// 3. Announce: once per incident, again when worse or after the quiet period; maintenance silent.
do {
    func reading(_ i: ServiceStatusLogic.Indicator, _ t: TimeInterval) -> ServiceStatusLogic.Reading {
        .init(indicator: i, description: "", readAt: now.addingTimeInterval(t))
    }
    let (n1, a1) = ServiceStatusLogic.announce(reading(.minor, 0), last: nil)
    expect(n1 && a1?.indicator == .minor, "first incident speaks")
    let (n2, a2) = ServiceStatusLogic.announce(reading(.minor, 600), last: a1)
    expect(!n2 && a2 == a1, "same incident is quiet")
    let (n3, a3) = ServiceStatusLogic.announce(reading(.major, 900), last: a2)
    expect(n3 && a3?.indicator == .major, "a worse incident speaks")
    let (n4, _) = ServiceStatusLogic.announce(reading(.minor, 1_200), last: a3)
    expect(!n4, "an easing incident is quiet")
    let (n5, _) = ServiceStatusLogic.announce(reading(.major, 7 * 3_600), last: a3)
    expect(n5, "after the quiet period it speaks again")
    let (n6, a6) = ServiceStatusLogic.announce(reading(.none, 1_500), last: a3)
    expect(!n6 && a6 == nil, "recovery clears the memory")
    let (n7, _) = ServiceStatusLogic.announce(reading(.minor, 1_600), last: a6)
    expect(n7, "the next incident after recovery speaks")
    let (n8, a8) = ServiceStatusLogic.announce(reading(.maintenance, 0), last: nil)
    expect(!n8 && a8 == nil, "maintenance never speaks")
}

if failures > 0 { print("\(failures) FAILED"); exit(1) }
print("ALL PASS")
