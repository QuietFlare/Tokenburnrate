import Foundation

public struct HourPoint: Codable, Hashable {
    public let hour: Int
    public let tokens: Int
    public init(hour: Int, tokens: Int) {
        self.hour = hour
        self.tokens = tokens
    }
}

public struct ModelUsage: Identifiable, Hashable, Codable {
    public var id: String { model }
    public let model: String
    public var messages: Int
    public var tokens: Int

    public var shortName: String {
        let m = model.lowercased()
        if m.contains("fable") { return "fable" }
        if m.contains("opus") { return "opus" }
        if m.contains("sonnet") { return "sonnet" }
        if m.contains("haiku") { return "haiku" }
        return model
    }
}

public struct SessionUsage: Identifiable, Hashable, Codable {
    public let id: String
    public let name: String
    public let tokens: Int
}

public struct DayUsage: Identifiable, Hashable, Codable {
    public let id: String
    public let date: Date
    public let tokens: Int
}

public struct UsageStats: Codable {
    public var todayTotal: Int = 0
    public var byModel: [ModelUsage] = []
    public var topSessions: [SessionUsage] = []
    public var hourlyCumulative: [HourPoint] = []
    public var daily: [DayUsage] = []
    public var sessionWindowTokens: Int = 0
    public var sessionWindowStart: Date?
    public var weeklyAllTokens: Int = 0
    public var weeklyFableOpusTokens: Int = 0
    public var nextWeeklyReset: Date?
    public var official: OfficialUsage?
    public var fetchFailure: OfficialUsage.FetchFailure?
    public var generatedAt: Date = .now

    public init() {}

    /// Only a sign-in can clear this one, and only the user can perform it.
    public var needsReauth: Bool { fetchFailure == .signedOut }

    public var displaySessionFraction: Double {
        if let o = official { return Double(o.sessionPercent) / 100 }
        return sessionWindowFraction
    }

    public var displaySessionReset: Date? {
        official?.sessionReset ?? sessionResetDate
    }

    public var displayWeekAllFraction: Double {
        if let pct = official?.weekAllPercent { return Double(pct) / 100 }
        return weeklyAllFraction
    }

    public var displayWeekModelFraction: Double? {
        if let pct = official?.weekModelPercent { return Double(pct) / 100 }
        return weeklyFableOpusTokens > 0 ? weeklyFableOpusFraction : nil
    }

    public var displayWeekModelLabel: String {
        official?.weekModelName?.lowercased() ?? "fable + opus"
    }

    public var isOfficial: Bool { official != nil }

    public static func exactTime(_ date: Date?) -> String {
        guard let date else { return "idle" }
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return time }
        let day = date.formatted(.dateTime.month(.abbreviated).day())
        return "\(day) \(time)"
    }

    public static func shortCountdown(to date: Date?) -> String {
        guard let date, date > .now else { return "soon" }
        let s = date.timeIntervalSince(.now)
        let d = Int(s) / 86400
        let h = (Int(s) % 86400) / 3600
        let m = (Int(s) % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    public var sessionResetDate: Date? {
        sessionWindowStart.map { $0.addingTimeInterval(5 * 3600) }
    }

    public var sessionWindowFraction: Double {
        guard let start = sessionWindowStart else { return 0 }
        return min(Date.now.timeIntervalSince(start) / (5 * 3600), 1)
    }

    public var sessionResetShortText: String {
        guard let reset = displaySessionReset else { return "idle" }
        let s = reset.timeIntervalSince(.now)
        guard s > 0 else { return "resets soon" }
        return String(format: "%d:%02d", Int(s) / 3600, (Int(s) % 3600) / 60)
    }

    public static var weeklyAllBudget: Int {
        let v = UserDefaults.standard.integer(forKey: "weeklyAllBudgetTokens")
        return v > 0 ? v : 100_000_000
    }

    public static var weeklyFableOpusBudget: Int {
        let v = UserDefaults.standard.integer(forKey: "weeklyFableOpusBudgetTokens")
        return v > 0 ? v : 30_000_000
    }

    public var weeklyAllFraction: Double {
        min(Double(weeklyAllTokens) / Double(Self.weeklyAllBudget), 1)
    }

    public var weeklyFableOpusFraction: Double {
        min(Double(weeklyFableOpusTokens) / Double(Self.weeklyFableOpusBudget), 1)
    }

    public var weeklyResetText: String {
        guard let next = nextWeeklyReset else { return "thu" }
        let s = max(next.timeIntervalSince(.now), 0)
        let d = Int(s) / 86400
        let h = (Int(s) % 86400) / 3600
        return d > 0 ? "\(d)d \(h)h" : "\(h)h"
    }

    public var dailyAverage: Int {
        let active = daily.filter { $0.tokens > 0 }
        guard !active.isEmpty else { return 0 }
        return active.map(\.tokens).reduce(0, +) / active.count
    }

    public var topModel: ModelUsage? { byModel.first }

    public var smartTip: String? {
        guard let top = topModel, todayTotal > 0 else { return nil }
        let share = Double(top.tokens) / Double(todayTotal)
        guard share > 0.5 else { return nil }
        let pct = Int((share * 100).rounded())
        let cheaper: String
        switch top.shortName {
        case "fable", "opus": cheaper = "sonnet"
        case "sonnet": cheaper = "haiku"
        default: return nil
        }
        return "\(top.shortName) is \(pct)% of today's burn · switch to \(cheaper) to stretch the week"
    }

    public static func formatTokens(_ n: Int) -> String {
        switch n {
        case ..<1000: return "\(n)"
        case ..<1_000_000: return String(format: "%.1fK", Double(n) / 1000)
        default: return String(format: "%.2fM", Double(n) / 1_000_000)
        }
    }

    public static var sample: UsageStats {
        var s = UsageStats()
        s.todayTotal = 3_670_000
        s.byModel = [
            ModelUsage(model: "claude-opus-5", messages: 141, tokens: 3_070_000),
            ModelUsage(model: "claude-haiku-4-5", messages: 54, tokens: 406_400),
            ModelUsage(model: "claude-fable-5", messages: 36, tokens: 185_800),
        ]
        s.topSessions = [
            SessionUsage(id: "1", name: "secret scan benchmark", tokens: 2_290_000),
            SessionUsage(id: "2", name: "teach me fundamentals of ML", tokens: 289_300),
            SessionUsage(id: "3", name: "macOS usage widget", tokens: 248_600),
        ]
        s.hourlyCumulative = [HourPoint(hour: 8, tokens: 1_080_000), HourPoint(hour: 9, tokens: 2_580_000), HourPoint(hour: 10, tokens: 3_670_000)]
        let cal = Calendar.current
        s.daily = (0..<30).reversed().map { i in
            let d = cal.date(byAdding: .day, value: -i, to: cal.startOfDay(for: .now))!
            let tok = [11_330_000, 1_950_000, 24_990_000, 904_700, 7_320_000, 1_930_000][i % 6]
            return DayUsage(id: "\(i)", date: d, tokens: i % 7 == 0 ? tok / 10 : tok)
        }
        s.sessionWindowTokens = 2_400_000
        s.sessionWindowStart = Date.now.addingTimeInterval(-78 * 60)
        s.weeklyAllTokens = 41_000_000
        s.weeklyFableOpusTokens = 21_900_000
        s.nextWeeklyReset = Date.now.addingTimeInterval(2 * 86400 + 22 * 3600)
        return s
    }
}
