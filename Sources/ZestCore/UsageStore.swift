import Foundation

/// Remembers which suggestions you pick, so frequent ones move up.
public final class UsageStore: @unchecked Sendable {
    struct Entry: Codable {
        var count: Int
        var last: Date
    }

    private let url: URL?
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private let saveQueue = DispatchQueue(label: "zest.usage")

    /// Entries beyond this are dropped, least recently used first.
    static let limit = 5000

    /// `url` nil keeps everything in memory.
    public init(url: URL?) {
        self.url = url
        if let url, let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        }
    }

    public func record(_ key: String) {
        guard !key.isEmpty else { return }
        lock.lock()
        var entry = entries[key] ?? Entry(count: 0, last: Date())
        entry.count += 1
        entry.last = Date()
        entries[key] = entry
        if entries.count > Self.limit {
            let oldest = entries.sorted { $0.value.last < $1.value.last }.prefix(entries.count - Self.limit)
            for (k, _) in oldest { entries.removeValue(forKey: k) }
        }
        let snapshot = entries
        lock.unlock()
        save(snapshot)
    }

    /// A score bonus: grows with use, shrinks when unused for weeks. At most 40, so a
    /// frequent fuzzy match never beats a prefix match.
    public func boost(_ key: String) -> Double {
        lock.lock()
        let entry = entries[key]
        lock.unlock()
        guard let entry else { return 0 }
        let days = max(0, Date().timeIntervalSince(entry.last) / 86_400)
        let recency = 1 / (1 + days / 14)
        return min(40, log2(Double(entry.count) + 1) * 10 * recency)
    }

    public func reset() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
        save([:])
    }

    private func save(_ snapshot: [String: Entry]) {
        guard let url else { return }
        saveQueue.async {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
