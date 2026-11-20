import Foundation

// THE STORE ITSELF, COMPILED AND DRIVEN. Until now `UsageBar/Stores/EarlyStartStore.swift` was the one
// file in this feature no suite compiled at all, so every rule it carries was held by reading its
// source as text - and a text lock cannot tell a rule from a sentence about a rule (spawnchecks.swift
// says so at length about its own span).
//
// It is built here against the real relay (the decision layer, the persisted shapes, the quiet
// window, the spawn's value type), the real CLI resolution and the real build variant. Four
// app-wide singletons it touches for reasons unrelated to early start are stood in for, and the
// reasoning for each - including what a stand-in cannot catch - is in storeharness.swift.
//
// WHAT IS NOT DRIVEN HERE, AND WHY, said plainly rather than left to be assumed: the spawn. A test
// binary is a build nobody installed, so `mayRun` is false in it by construction (`BuildVariant
// .isUnshipped`), and `evaluate` returns at that gate before it decides anything. That gate is not
// an obstacle to be worked around - it is the thing standing between an assertion run and a real
// subscription's window, since the executable this store would reach for is the `claude` on this
// machine's PATH. So nothing below asks `evaluate` to send, and a future check that flips that gate
// would be asking a test suite to spend somebody's quota.
//
// The rules that ARE driven are the ones the relay's cost floor rests on, and they were all
// source-scrape assertions before: what the preference writers touch, and what the arming gate
// answers.
@MainActor
func runStoreChecks() {
    let defaults = UserDefaults.standard
    // The keys as the store spells them. Private there, so they are written out here and pinned to
    // the source in the same breath: a rename that this file did not follow would otherwise leave
    // every check below reading and writing a key nothing uses, which is green for a store that
    // does the opposite of what is asserted.
    let stateKey = "\(BrandPaths.reverseDNS).earlyStart.state"
    let enabledKey = "\(BrandPaths.reverseDNS).earlyStart.enabled"
    let noticeKey = "\(BrandPaths.reverseDNS).earlyStart.noticeVersion"
    let store = (try? String(contentsOfFile: "UsageBar/Stores/EarlyStartStore.swift",
                             encoding: .utf8)) ?? ""
    // UsageBar spells every key under BrandPaths.reverseDNS, so the source carries the
    // interpolation and these checks carry what it evaluates to.
    let spelled = { (suffix: String) in "\"\\(BrandPaths.reverseDNS).earlyStart.\(suffix)\"" }
    expect(store.contains("static let state = \(spelled("state"))")
             && store.contains("static let enabled = \(spelled("enabled"))")
             && store.contains("static let noticeVersion = \(spelled("noticeVersion"))")
             && stateKey.hasPrefix(BrandPaths.reverseDNS + ".")
             && enabledKey.hasPrefix(BrandPaths.reverseDNS + ".")
             && noticeKey.hasPrefix(BrandPaths.reverseDNS + "."),
           "the keys these checks drive are the keys the store writes")

    // The state a machine has on disk after a message went out twenty minutes ago: the mark is the
    // whole record of "this account has had its message inside the last five hours".
    var seeded = EarlyStartState()
    seeded.marks["a"] = EarlyStartMark(attemptedAt: at("2026-08-24 07:10"))
    let seededData = try! JSONEncoder().encode(seeded)

    // The gate in front of the first message, driven through the defaults the real store reads at
    // init. Set BEFORE the singleton is first touched, since that is when it reads them.
    defaults.set(true, forKey: enabledKey)
    // ONE, NOT ZERO, and that is the whole of what this seed asserts. The behaviour changed after
    // the first notice shipped, so a machine that answered the MORNING SCHEDULE's notice has
    // consented to something that no longer exists (`EarlyStartLogic.noticeVersion`). Zero cannot
    // tell a store that asks "which telling was answered" from one that asks "was any", because
    // both answer no to it; one is the value the two questions disagree about.
    defaults.set(1, forKey: noticeKey)
    defaults.set(seededData, forKey: stateKey)

    // UsageBar ships early start closed (BrimFeatures.earlyStart). With the gate closed, the very
    // machine seeded above (switched on, notice not yet answered) is neither on nor asking.
    expect(!BrimFeatures.earlyStart && EarlyStartStore.shared.isEnabled == false,
           "UsageBar's shipped store has early start off whatever the defaults say")
    let closed = EarlyStartStore(featureEnabled: false)
    expect(!closed.isEnabled && !closed.showsNotice && !closed.isArmed,
           "with the gate closed nothing is enabled, no notice is shown and nothing is armed")
    closed.start()
    closed.evaluate(accounts: [], launchHomes: [:])
    expect(defaults.data(forKey: stateKey) == seededData
             && defaults.integer(forKey: noticeKey) == 1,
           "…and starting and evaluating it writes nothing")

    // From here on the checks open the gate and drive the store behind it.
    let relay = EarlyStartStore(featureEnabled: true)
    expect(relay.isEnabled && !relay.noticeAcknowledged,
           "a machine that only answered the morning notice has not answered this one")
    expect(relay.showsNotice && !relay.isArmed,
           "…so the panel carries the notice and nothing is armed to send")
    relay.acknowledgeNotice()
    expect(relay.isArmed && !relay.showsNotice,
           "answering it arms the relay and takes the notice down")
    expect(defaults.integer(forKey: noticeKey) == EarlyStartLogic.noticeVersion,
           "…and WHICH telling was answered is what is written down, not that one was")
    relay.setEnabled(false)
    expect(!relay.isArmed && !relay.showsNotice,
           "switching the feature off disarms it without asking for the notice again")
    relay.setEnabled(true)
    expect(relay.isArmed, "…and switching it back on arms it again, the answer still standing")

    // THE COST FLOOR ACROSS EVERY PREFERENCE PATH, which is what this file was written for. The
    // marks are the only record that an account has already had its message; the build before the
    // relay cleared them here and handed the suppression to a stamp that no longer exists, so a
    // preference path that writes state again gives back the guarantee the panel notice and the
    // Settings row both state in words. Asserted as BYTES rather than as a decoded value: what
    // matters is that nothing rewrote the payload at all.
    let quiet = EarlyStartQuietHours(isEnabled: true, startHour: 23, startMinute: 30,
                                     endHour: 7, endMinute: 15)
    relay.setQuietHours(quiet)
    relay.setEnabled(false)
    relay.setEnabled(true)
    relay.acknowledgeNotice()
    expect(defaults.data(forKey: stateKey) == seededData,
           "no preference path rewrites the relay's own state: the five-hour floor survives them")
    expect(relay.quietHours == quiet, "…and the silence window it was asked for is what it holds")
    // Round-tripped through the defaults rather than only through the property, since a store that
    // kept the value in memory and wrote nothing would answer the line above and forget by morning.
    expect(defaults.integer(forKey: "\(BrandPaths.reverseDNS).earlyStart.quiet.startHour") == 23
             && defaults.integer(forKey: "\(BrandPaths.reverseDNS).earlyStart.quiet.endMinute") == 15
             && defaults.bool(forKey: "\(BrandPaths.reverseDNS).earlyStart.quiet.enabled"),
           "…written down, so tomorrow's launch reads the same window")

    // AND AN EVALUATION IN A PROCESS NOBODY INSTALLED WRITES NOTHING, which is the gate named at the
    // top of this file. Handed an empty fleet, so that the day this assertion is ever wrong it is
    // wrong quietly rather than by spawning something.
    relay.evaluate(accounts: [], launchHomes: [:])
    expect(defaults.data(forKey: stateKey) == seededData,
           "an evaluation with nothing to decide leaves the payload alone")

    for key in [stateKey, enabledKey, noticeKey,
                "\(BrandPaths.reverseDNS).earlyStart.quiet.enabled",
                "\(BrandPaths.reverseDNS).earlyStart.quiet.startHour",
                "\(BrandPaths.reverseDNS).earlyStart.quiet.startMinute",
                "\(BrandPaths.reverseDNS).earlyStart.quiet.endHour",
                "\(BrandPaths.reverseDNS).earlyStart.quiet.endMinute"] {
        defaults.removeObject(forKey: key)
    }
    // The default behind the gate: a switch nobody ever touched reads as on.
    expect(EarlyStartStore(featureEnabled: true).isEnabled
             && !EarlyStartStore(featureEnabled: false).isEnabled,
           "a never-chosen switch is on once the gate is open, and off while it is closed")
}
