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

    /// Why a refresh failed. Persisted so the widget can say what to do about it
    /// rather than leaving a silent gap that looks like a first launch.
    public enum FetchFailure: String, Codable, Error {
        case cliNotFound
        case signedOut
        case cliFailed
        case unrecognizedOutput

        public var headline: String {
            switch self {
            case .cliNotFound: return "claude CLI not found"
            case .signedOut: return "Claude Code is signed out"
            case .cliFailed: return "claude CLI returned an error"
            case .unrecognizedOutput: return "couldn't read /usage output"
            }
        }

        public var hint: String {
            switch self {
            case .cliNotFound: return "install Claude Code, then reopen TokenBurnrate"
            case .signedOut: return "run: claude auth login"
            case .cliFailed: return "try running: claude -p \"/usage\""
            case .unrecognizedOutput: return "TokenBurnrate may need an update"
            }
        }
    }

    public struct Status: Codable {
        public var failure: FetchFailure?
        public var at: Date
    }

    /// Refreshes are throttled to 5 minutes, so anything much older means they are
    /// failing, or nothing has driven one in a while.
    public var isStale: Bool {
        Date.now.timeIntervalSince(fetchedAt) > 45 * 60
    }

    /// The window these percentages describe has rolled over, so they no longer
    /// describe anything current and must not be drawn as if they did.
    public var isExpired: Bool {
        if let sessionReset, sessionReset < .now { return true }
        return Date.now.timeIntervalSince(fetchedAt) > 6 * 3600
    }

    private static var cacheDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TokenBurnrate", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var cacheURL: URL {
        cacheDirectory.appendingPathComponent("official-usage.json")
    }

    private static var statusURL: URL {
        cacheDirectory.appendingPathComponent("fetch-status.json")
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

    public static func loadStatus() -> Status? {
        guard let data = try? Data(contentsOf: statusURL),
              let status = try? JSONDecoder().decode(Status.self, from: data) else { return nil }
        return status
    }

    public static func record(_ failure: FetchFailure) {
        if let data = try? JSONEncoder().encode(Status(failure: failure, at: .now)) {
            try? data.write(to: statusURL, options: .atomic)
        }
    }

    public static func clearFailure() {
        try? FileManager.default.removeItem(at: statusURL)
    }

    public static var cacheAge: TimeInterval {
        guard let cached = loadCached() else { return .infinity }
        return Date.now.timeIntervalSince(cached.fetchedAt)
    }

    /// A failing fetch never advances `fetchedAt`, so `cacheAge` alone would let
    /// every transcript write spawn another doomed CLI run. Back off on failure too.
    public static func shouldAttemptFetch() -> Bool {
        if let status = loadStatus(), status.failure != nil,
           Date.now.timeIntervalSince(status.at) < 300 { return false }
        return cacheAge > 300
    }

    /// The CLI a refresh would run, so an offered sign-in uses that same binary
    /// rather than whatever a login shell's PATH happens to resolve.
    public static func binaryPath() -> String? { claudeBinary() }

    public static func fetchViaCLI() -> Result<OfficialUsage, FetchFailure> {
        guard let bin = claudeBinary() else { return .failure(.cliNotFound) }
        guard let run = run(bin, ["-p", "/usage"]), run.status == 0 else { return .failure(.cliFailed) }
        if let usage = parse(run.output) { return .success(usage) }
        // When the CLI cannot authenticate, `/usage` still exits 0 and prints the
        // generic cost summary, so an unparsable run is ambiguous until we ask.
        return .failure(isSignedIn(bin) ? .unrecognizedOutput : .signedOut)
    }

    private static func isSignedIn(_ bin: String) -> Bool {
        // `auth status` exits 1 precisely when signed out, so the exit code is part of
        // the answer here, not a reason to throw away the JSON it printed on stdout.
        guard let run = run(bin, ["auth", "status"]),
              let json = try? JSONSerialization.jsonObject(with: Data(run.output.utf8)) as? [String: Any],
              let loggedIn = json["loggedIn"] as? Bool else {
            return true  // Never claim signed-out on an inconclusive answer.
        }
        return loggedIn
    }

    private struct Run {
        var status: Int32
        var output: String
    }

    private static func run(_ bin: String, _ args: [String]) -> Run? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = args
        let binDir = (bin as NSString).deletingLastPathComponent
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(binDir):/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        process.environment = env
        process.currentDirectoryURL = cacheDirectory
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
        return Run(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    private static let binaryLock = NSLock()
    private static var resolvedBinary: (fingerprint: String, path: String)?

    private static func claudeBinary() -> String? {
        let candidates = candidateBinaries()
        let fingerprint = candidates.joined(separator: "\n")

        binaryLock.lock()
        defer { binaryLock.unlock() }

        if let resolved = resolvedBinary, resolved.fingerprint == fingerprint,
           FileManager.default.isExecutableFile(atPath: resolved.path) {
            return resolved.path
        }
        guard let best = newest(among: candidates) ?? binaryViaLoginShell() else {
            resolvedBinary = nil
            return nil
        }
        resolvedBinary = (fingerprint, best)
        return best
    }

    /// Every install we know how to find. Version-numbered directories mean the set
    /// changes on update, which is what invalidates the resolved binary above.
    private static func candidateBinaries() -> [String] {
        let fm = FileManager.default
        let home = NSHomeDirectory()

        var paths = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
        ]
        // nvm-managed npm globals: ~/.nvm/versions/node/*/bin/claude
        let nvmDir = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmDir) {
            paths += versions.map { "\(nvmDir)/\($0)/bin/claude" }
        }
        // The Claude desktop app keeps its own copy, and updates it independently of
        // any CLI on PATH, so it is often the newest one present.
        let desktopDir = "\(home)/Library/Application Support/Claude/claude-code"
        if let versions = try? fm.contentsOfDirectory(atPath: desktopDir) {
            paths += versions.map { "\(desktopDir)/\($0)/claude.app/Contents/MacOS/claude" }
        }
        return paths.filter { fm.isExecutableFile(atPath: $0) }.sorted()
    }

    /// Picks by reported version rather than by list order, so a stale install never
    /// shadows a newer one just because it sits earlier in the search path.
    private static func newest(among candidates: [String]) -> String? {
        var best: (version: [Int], path: String)?
        for path in candidates {
            guard let version = cliVersion(of: path) else { continue }
            if let current = best, !current.version.lexicographicallyPrecedes(version) { continue }
            best = (version, path)
        }
        return best?.path ?? candidates.first
    }

    private static func cliVersion(of path: String) -> [Int]? {
        guard let run = run(path, ["--version"]), run.status == 0,
              let m = run.output.firstMatch(of: /(\d+)\.(\d+)\.(\d+)/) else { return nil }
        return [Int(m.1) ?? 0, Int(m.2) ?? 0, Int(m.3) ?? 0]
    }

    /// Last resort: an interactive login shell so nvm/asdf init in .zshrc runs.
    private static func binaryViaLoginShell() -> String? {
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/bin/zsh")
        which.arguments = ["-lic", "which claude"]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = Pipe()
        guard (try? which.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        which.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self)
            .split(separator: "\n").last.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
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

        guard let tm = lower.firstMatch(of: /(\d{1,2})(?::(\d{2}))?\s*(am|pm)/) else { return nil }
        var hour = Int(tm.1) ?? 0
        let minute = tm.2.flatMap { Int($0) } ?? 0
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
