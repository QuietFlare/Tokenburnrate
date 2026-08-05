import Foundation

private struct TokenEvent: Codable {
    let t: Double
    let m: String
    let k: Int
}

private struct FileCacheEntry: Codable {
    var size: Int
    var offset: Int
    var name: String?
    var events: [TokenEvent]
}

public enum UsageParser {

    public static func claudeDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }

    public static func projectsDirectory() -> URL {
        claudeDirectory().appendingPathComponent("projects")
    }

    private static let supportDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TokenBurnrate", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static var cacheURL: URL { supportDir.appendingPathComponent("today-cache.json") }
    private static var historyURL: URL { supportDir.appendingPathComponent("daily-history.json") }

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public static func loadStats() -> UsageStats {
        let fm = FileManager.default
        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let cutoff = min(today, now.addingTimeInterval(-5 * 3600))

        var cache: [String: FileCacheEntry] =
            (try? JSONDecoder().decode([String: FileCacheEntry].self, from: Data(contentsOf: cacheURL))) ?? [:]

        var candidates: [(path: String, size: Int)] = []
        if let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDirectory(), includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) {
            for dir in projectDirs {
                guard let files = try? fm.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                    options: .skipsHiddenFiles
                ) else { continue }
                for file in files where file.pathExtension == "jsonl" {
                    guard let vals = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                          let mod = vals.contentModificationDate, mod >= cutoff,
                          let size = vals.fileSize else { continue }
                    candidates.append((file.path, size))
                }
            }
        }

        let stale = candidates.filter { cache[$0.path]?.size != $0.size }
        if !stale.isEmpty {
            let lock = NSLock()
            var updates: [String: FileCacheEntry] = [:]
            DispatchQueue.concurrentPerform(iterations: stale.count) { i in
                let (path, size) = stale[i]
                if let entry = parseFile(path: path, size: size, resumeFrom: cache[path]) {
                    lock.lock()
                    updates[path] = entry
                    lock.unlock()
                }
            }
            for (path, entry) in updates { cache[path] = entry }
        }

        let livePaths = Set(candidates.map(\.path))
        cache = cache.filter { livePaths.contains($0.key) }
        if !stale.isEmpty, let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }

        var stats = aggregate(cache: cache, calendar: calendar, now: now, today: today)

        let todayFableOpus = stats.byModel
            .filter { ["fable", "opus"].contains($0.shortName) }
            .map(\.tokens).reduce(0, +)
        let history = updateHistory(
            todayTotal: stats.todayTotal, todayFableOpus: todayFableOpus,
            calendar: calendar, today: today
        )
        stats.daily = (0..<30).reversed().compactMap { i in
            guard let d = calendar.date(byAdding: .day, value: -i, to: today) else { return nil }
            let key = dayKeyFormatter.string(from: d)
            return DayUsage(id: key, date: d, tokens: history[key]?.total ?? 0)
        }

        let (lastReset, nextReset) = weeklyResetDates(now: now, calendar: calendar)
        stats.nextWeeklyReset = nextReset
        let resetDay = calendar.startOfDay(for: lastReset)
        for (key, record) in history {
            guard let d = dayKeyFormatter.date(from: key), d >= resetDay else { continue }
            stats.weeklyAllTokens += record.total
            stats.weeklyFableOpusTokens += record.fo
        }

        stats.official = OfficialUsage.loadCached()
        return stats
    }

    private static func weeklyResetDates(now: Date, calendar: Calendar) -> (last: Date, next: Date) {
        var comps = DateComponents()
        comps.weekday = 5
        comps.hour = 9
        let next = calendar.nextDate(after: now, matching: comps, matchingPolicy: .nextTime) ?? now
        let last = calendar.date(byAdding: .day, value: -7, to: next) ?? now
        return (last, next)
    }

    private static func parseFile(path: String, size: Int, resumeFrom prior: FileCacheEntry?) -> FileCacheEntry? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        var entry = prior ?? FileCacheEntry(size: 0, offset: 0, name: nil, events: [])
        if entry.offset > size { entry = FileCacheEntry(size: 0, offset: 0, name: nil, events: []) }

        if entry.offset > 0 { try? handle.seek(toOffset: UInt64(entry.offset)) }
        guard let data = try? handle.readToEnd(), !data.isEmpty else {
            entry.size = size
            return entry
        }

        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]

        let consumed = data.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress, raw.count > 0 else { return 0 }
            var i = raw.count - 1
            while i >= 0, base.load(fromByteOffset: i, as: UInt8.self) != 0x0A { i -= 1 }
            return i + 1
        }
        guard consumed > 0 else {
            entry.size = size
            return entry
        }

        let text = String(decoding: data.prefix(consumed), as: UTF8.self)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let hasUsage = line.contains("\"usage\":") && line.contains("\"type\":\"assistant\"")
            let needName = entry.name == nil && line.contains("\"type\":\"user\"")
            guard hasUsage || needName else { continue }

            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = obj["type"] as? String else { continue }

            if type == "user", entry.name == nil,
               let msg = obj["message"] as? [String: Any],
               let content = msg["content"] as? String {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, !trimmed.hasPrefix("<"), !trimmed.hasPrefix("Caveat") {
                    entry.name = String(trimmed.prefix(60))
                }
                continue
            }

            guard type == "assistant",
                  let msg = obj["message"] as? [String: Any],
                  let usage = msg["usage"] as? [String: Any],
                  let tsString = obj["timestamp"] as? String,
                  let ts = isoFrac.date(from: tsString) ?? isoPlain.date(from: tsString)
            else { continue }

            let tokens = (usage["input_tokens"] as? Int ?? 0)
                + (usage["output_tokens"] as? Int ?? 0)
                + (usage["cache_creation_input_tokens"] as? Int ?? 0)
            guard tokens > 0 else { continue }

            let model = msg["model"] as? String ?? "unknown"
            entry.events.append(TokenEvent(t: ts.timeIntervalSince1970, m: model, k: tokens))
        }

        entry.offset += consumed
        entry.size = entry.offset
        return entry
    }

    private static func aggregate(
        cache: [String: FileCacheEntry], calendar: Calendar, now: Date, today: Date
    ) -> UsageStats {
        var stats = UsageStats()
        var modelTokens: [String: (msgs: Int, tokens: Int)] = [:]
        var sessionTokens: [String: Int] = [:]
        var sessionNames: [String: String] = [:]
        var hourly: [Int: Int] = [:]
        var earliestInWindow: Date?
        let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)

        for (path, entry) in cache {
            let url = URL(fileURLWithPath: path)
            let sessionID = url.deletingPathExtension().lastPathComponent
            if let name = entry.name {
                sessionNames[sessionID] = name
            } else {
                let segments = url.deletingLastPathComponent().lastPathComponent
                    .split(separator: "-").filter { !$0.isEmpty }
                sessionNames[sessionID] = segments.suffix(2).joined(separator: " ")
            }

            for event in entry.events {
                let ts = Date(timeIntervalSince1970: event.t)

                if ts >= fiveHoursAgo, ts <= now {
                    stats.sessionWindowTokens += event.k
                    if earliestInWindow == nil || ts < earliestInWindow! { earliestInWindow = ts }
                }

                guard calendar.startOfDay(for: ts) == today else { continue }
                stats.todayTotal += event.k
                var m = modelTokens[event.m] ?? (0, 0)
                m.msgs += 1
                m.tokens += event.k
                modelTokens[event.m] = m
                sessionTokens[sessionID, default: 0] += event.k
                hourly[calendar.component(.hour, from: ts), default: 0] += event.k
            }
        }

        stats.byModel = modelTokens
            .filter { !$0.key.hasPrefix("<") }
            .map { ModelUsage(model: $0.key, messages: $0.value.msgs, tokens: $0.value.tokens) }
            .sorted { $0.tokens > $1.tokens }

        stats.topSessions = sessionTokens
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { SessionUsage(id: $0.key, name: sessionNames[$0.key] ?? String($0.key.prefix(8)), tokens: $0.value) }

        var running = 0
        stats.hourlyCumulative = hourly.keys.sorted().map { h in
            running += hourly[h]!
            return HourPoint(hour: h, tokens: running)
        }

        stats.sessionWindowStart = earliestInWindow
        stats.generatedAt = now
        return stats
    }

    struct DayRecord: Codable {
        var total: Int
        var fo: Int
    }

    private static func updateHistory(
        todayTotal: Int, todayFableOpus: Int, calendar: Calendar, today: Date
    ) -> [String: DayRecord] {
        var history: [String: DayRecord]
        if let data = try? Data(contentsOf: historyURL),
           let decoded = try? JSONDecoder().decode([String: DayRecord].self, from: data) {
            history = decoded
        } else if let data = try? Data(contentsOf: historyURL),
                  let legacy = try? JSONDecoder().decode([String: Int].self, from: data) {
            history = legacy.mapValues { DayRecord(total: $0, fo: 0) }
        } else {
            history = [:]
        }

        history[dayKeyFormatter.string(from: today)] = DayRecord(total: todayTotal, fo: todayFableOpus)
        if history.count > 60 {
            let sorted = history.keys.sorted(by: >)
            for key in sorted.dropFirst(60) { history.removeValue(forKey: key) }
        }
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: historyURL, options: .atomic)
        }
        return history
    }
}
