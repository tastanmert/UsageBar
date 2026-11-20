import Foundation

/// Snapshot fixtures for the UsageBar panel model and the screenshot renderer. Shaped like the
/// file UsageBar publishes (`~/.usagebar/snapshot.json`, version 2); no real labels or homes.
enum BrimFixtures {
    /// 2026-11-14 14:14 UTC, the moment every fixture is read at.
    static let now = Date(timeIntervalSince1970: 1_794_665_640)

    static func at(_ minutes: Double) -> String {
        ISO8601DateFormatter().string(from: now.addingTimeInterval(minutes * 60))
    }

    static func decode(_ json: String) -> UsageSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        } catch {
            fatalError("fixture does not decode: \(error)")
        }
    }

    static func snapshot(generatedMinutesAgo: Double = 1, _ accounts: [String],
                         order: [String]? = nil) -> UsageSnapshot {
        let orderJSON = order.map { ", \"accountOrder\": [" + $0.map { "\"\($0)\"" }.joined(separator: ",") + "]" } ?? ""
        return decode("""
        {"version": 2, "generatedAt": "\(at(-generatedMinutesAgo))", "accounts": [\(accounts.joined(separator: ","))]\(orderJSON)}
        """)
    }

    static func claude(_ id: String, _ label: String, plan: String, five: Double?, fiveIn: Double?,
                       weekly: Double?, weeklyIn: Double?, fable: Double? = nil, fableIn: Double? = nil,
                       modelName: String = "Fable", stale: Bool = false) -> String {
        var fields = [#""id": "claude:\#(id)""#, #""provider": "claude""#, #""label": "\#(label)""#,
                      #""plan": "\#(plan)""#, #""isStale": \#(stale)"#, #""lastRefreshFailed": false"#,
                      #""resetState": "notSupported""#, #""refreshedAt": "\#(at(-3))""#]
        if let five { fields.append(#""sessionRemaining": \#(five)"#) }
        if let fiveIn { fields.append(#""sessionResetsAt": "\#(at(fiveIn))""#) }
        if let weekly { fields.append(#""weeklyRemaining": \#(weekly)"#) }
        if let weeklyIn { fields.append(#""weeklyResetsAt": "\#(at(weeklyIn))""#) }
        if let fable {
            fields.append(#""modelRemaining": \#(fable)"#)
            fields.append(#""modelWindowName": "\#(modelName)""#)
            if let fableIn { fields.append(#""modelResetsAt": "\#(at(fableIn))""#) }
        }
        return "{" + fields.joined(separator: ", ") + "}"
    }

    static func codex(_ id: String, _ label: String, plan: String, five: Double? = nil,
                      fiveIn: Double? = nil, weekly: Double?, weeklyIn: Double?, credits: Int?) -> String {
        var fields = [#""id": "codex:\#(id)""#, #""provider": "codex""#, #""label": "\#(label)""#,
                      #""plan": "\#(plan)""#, #""isStale": false"#, #""lastRefreshFailed": false"#,
                      #""refreshedAt": "\#(at(-1))""#]
        if let five { fields.append(#""sessionRemaining": \#(five)"#) }
        if let fiveIn { fields.append(#""sessionResetsAt": "\#(at(fiveIn))""#) }
        if let weekly { fields.append(#""weeklyRemaining": \#(weekly)"#) }
        if let weeklyIn { fields.append(#""weeklyResetsAt": "\#(at(weeklyIn))""#) }
        if let credits {
            fields.append(#""resetCreditsAvailable": \#(credits)"#)
            fields.append(#""resetCreditsExpiryUnknown": false"#)
            fields.append(#""resetState": "\#(credits > 0 ? "available" : "used")""#)
            if credits > 0 { fields.append(#""resetCreditsNextExpiry": "\#(at(60 * 24 * 28))""#) }
        }
        return "{" + fields.joined(separator: ", ") + "}"
    }

    /// The spec's sample fleet: Main / Work / Spare on Claude, Info / Backoffice on Codex.
    static func normal(generatedMinutesAgo: Double = 1, backofficeFive: Double = 0) -> UsageSnapshot {
        snapshot(generatedMinutesAgo: generatedMinutesAgo, [
            claude(".claude", "Main", plan: "Max 20x", five: 62, fiveIn: 134, weekly: 39, weeklyIn: 60 * 67,
                   fable: 28, fableIn: 60 * 67),
            claude(".claude2", "Work", plan: "Pro", five: 9, fiveIn: 47, weekly: 56, weeklyIn: 60 * 90),
            claude(".claude3", "Spare", plan: "Pro", five: 94, fiveIn: 291, weekly: 73, weeklyIn: 60 * 110),
            codex(".codex", "Info", plan: "Pro", five: 78, fiveIn: 185, weekly: 42, weeklyIn: 60 * 45, credits: 2),
            codex(".codex2", "Backoffice", plan: "Plus", five: backofficeFive, fiveIn: 92, weekly: 6,
                  weeklyIn: 60 * 45, credits: 0),
        ])
    }

    /// Every account at a wall.
    static let allLimited = snapshot([
        claude(".claude", "Main", plan: "Max 20x", five: 0, fiveIn: 92, weekly: 40, weeklyIn: 3000),
        claude(".claude2", "Work", plan: "Pro", five: 30, fiveIn: 20, weekly: 0, weeklyIn: 600),
        codex(".codex", "Info", plan: "Pro", weekly: 0, weeklyIn: 2000, credits: 1),
    ])

    /// UsageBar's own shape today: Codex reports no 5h window, Claude no reset credits, two Codex
    /// accounts share a label.
    static let noFiveHourCodex = snapshot([
        claude(".claude", "Claude Max", plan: "Max", five: 100, fiveIn: nil, weekly: 35, weeklyIn: 5000,
               fable: 41, fableIn: 5000),
        codex(".codex", "Codex 100", plan: "Team", weekly: 5, weeklyIn: 2800, credits: 1),
        codex(".codex2", "Codex 100", plan: "Team", weekly: 5, weeklyIn: 5200, credits: 1),
    ])

    static let noResetData = snapshot([
        claude(".claude", "Main", plan: "Max 20x", five: 62, fiveIn: 134, weekly: 39, weeklyIn: 4000),
        claude(".claude2", "Work", plan: "Pro", five: 20, fiveIn: 47, weekly: 56, weeklyIn: 5000),
    ])

    static let empty = snapshot([])

    static func refreshFailure() -> UsageSnapshot {
        var snapshot = normal()
        snapshot.accounts[0].lastRefreshFailed = true
        snapshot.accounts[0].error = "Kota bilgisi alınamadı: sorun sürerse /login komutunu çalıştırın"
        snapshot.accounts[0].errorDetail = "Örnek tanı: sağlayıcı zamanında yanıt vermedi."
        snapshot.accounts[0].refreshedAt = now.addingTimeInterval(-34 * 60)
        let codex = snapshot.accounts.firstIndex { $0.provider == "codex" }!
        snapshot.accounts[codex].lastRefreshFailed = true
        snapshot.accounts[codex].error = "Kota bilgisi alınamadı"
        snapshot.accounts[codex].codexCredit = .init(balance: 12.75)
        snapshot.accounts[codex].refreshedAt = now.addingTimeInterval(-86400)
        return snapshot
    }

    /// UsageBar's own Claude reset read for `normal()`: Main holds a full and a Fable reset (the
    /// shape of the reset-inventory branch's Max fixture), Work's are spent, Spare's login is
    /// waiting for UsageBar to refresh it.
    static let claudeResets: [String: BrimPanelModel.ClaudeResets] = [
        "claude:.claude": .init(credit: .init(usedCents: 541, limitCents: 2000, enabled: true), state: .read([
            .init(kind: .fable, left: 1, endsAt: ISO8601DateFormatter().date(from: "2027-03-09T07:59:00Z")!),
            .init(kind: .full, left: 1, endsAt: ISO8601DateFormatter().date(from: "2026-12-10T22:00:00Z")!),
        ]), problem: nil),
        "claude:.claude2": .init(credit: .init(usedCents: 541, enabled: true), state: .read([
            .init(kind: .full, left: 0, endsAt: ISO8601DateFormatter().date(from: "2026-12-10T22:00:00Z")!),
        ]), problem: nil),
        "claude:.claude3": .init(state: .unknown, problem: .loginExpiring),
    ]
}
