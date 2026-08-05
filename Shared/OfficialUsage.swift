import Foundation

public struct OfficialUsage: Codable {
    public var sessionPercent: Int
    public var sessionReset: Date?
    public var weekAllPercent: Int?
    public var weekAllReset: Date?
    public var weekModelName: String?
    public var weekModelPercent: Int?
    public var weekModelReset: Date?
    public var fetchedAt: Date

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TokenBurnrate", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("official-usage.json")
    }

    public static func loadCached() -> OfficialUsage? {
        guard let data = try? Data(contentsOf: cacheURL),
              let usage = try? JSONDecoder().decode(OfficialUsage.self, from: data) else { return nil }
        return usage
    }

    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Self.cacheURL, options: .atomic)
        }
    }

    public static var cacheAge: TimeInterval {
        guard let cached = loadCached() else { return .infinity }
        return Date.now.timeIntervalSince(cached.fetchedAt)
    }

    public static func fetchViaCLI() -> OfficialUsage? {
        guard let bin = claudeBinary() else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = ["-p", "/usage"]
        let neutralDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TokenBurnrate", isDirectory: true)
        try? FileManager.default.createDirectory(at: neutralDir, withIntermediateDirectories: true)
        process.currentDirectoryURL = neutralDir
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else { return nil }
        return parse(output)
    }

    private static func claudeBinary() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/bin/zsh")
        which.arguments = ["-lc", "which claude"]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = Pipe()
        guard (try? which.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        which.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    static func parse(_ output: String) -> OfficialUsage? {
        var result = OfficialUsage(sessionPercent: 0, fetchedAt: .now)
        var foundSession = false

        for line in output.split(separator: "\n") {
            if let m = line.firstMatch(of: /Current session: (\d+)% used · resets ([^(]+)\(([^)]+)\)/) {
                result.sessionPercent = Int(m.1) ?? 0
                result.sessionReset = parseResetDate(String(m.2), timeZoneID: String(m.3))
                foundSession = true
            } else if let m = line.firstMatch(of: /Current week \(([^)]+)\): (\d+)% used · resets ([^(]+)\(([^)]+)\)/) {
                let name = String(m.1)
                let pct = Int(m.2)
                let reset = parseResetDate(String(m.3), timeZoneID: String(m.4))
                if name.lowercased() == "all models" {
                    result.weekAllPercent = pct
                    result.weekAllReset = reset
                } else {
                    result.weekModelName = name
                    result.weekModelPercent = pct
                    result.weekModelReset = reset
                }
            }
        }
        return foundSession ? result : nil
    }

    private static func parseResetDate(_ text: String, timeZoneID: String) -> Date? {
        let tz = TimeZone(identifier: timeZoneID) ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)

        guard let tm = lower.firstMatch(of: /(\d{1,2}):(\d{2})\s*(am|pm)/) else { return nil }
        var hour = Int(tm.1) ?? 0
        let minute = Int(tm.2) ?? 0
        if tm.3 == "pm" && hour != 12 { hour += 12 }
        if tm.3 == "am" && hour == 12 { hour = 0 }

        let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                      "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]

        var dayBase: Date
        if lower.contains("tomorrow") {
            dayBase = cal.date(byAdding: .day, value: 1, to: .now) ?? .now
        } else if let dm = lower.firstMatch(of: /([a-z]{3,9})\s+(\d{1,2})/),
                  let month = months[String(dm.1.prefix(3))],
                  let day = Int(dm.2) {
            var comps = cal.dateComponents([.year], from: .now)
            comps.month = month
            comps.day = day
            comps.hour = hour
            comps.minute = minute
            guard var date = cal.date(from: comps) else { return nil }
            if date < Date.now.addingTimeInterval(-86400) {
                date = cal.date(byAdding: .year, value: 1, to: date) ?? date
            }
            return date
        } else {
            dayBase = .now
        }

        var comps = cal.dateComponents([.year, .month, .day], from: dayBase)
        comps.hour = hour
        comps.minute = minute
        guard var date = cal.date(from: comps) else { return nil }
        if date < .now, !lower.contains("tomorrow") {
            date = cal.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return date
    }
}
