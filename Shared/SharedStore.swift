import Foundation
import Security

public enum SharedStore {
    /// Read from the running binary's own `application-groups` entitlement, which
    /// the build resolves from `$(TeamIdentifierPrefix)`. Keeps the team
    /// identifier out of source while staying correct for any signing team.
    public static let groupID: String = {
        guard let task = SecTaskCreateFromSelf(nil),
              let groups = SecTaskCopyValueForEntitlement(
                task, "com.apple.security.application-groups" as CFString, nil
              ) as? [String]
        else { return "" }
        return groups.first ?? ""
    }()

    private static var snapshotURL: URL? {
        guard !groupID.isEmpty else { return nil }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("stats-snapshot.json")
    }

    public static func save(_ stats: UsageStats) {
        guard let url = snapshotURL,
              let data = try? JSONEncoder().encode(stats) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public static func load() -> UsageStats? {
        guard let url = snapshotURL,
              let data = try? Data(contentsOf: url),
              let stats = try? JSONDecoder().decode(UsageStats.self, from: data) else { return nil }
        return stats
    }
}
