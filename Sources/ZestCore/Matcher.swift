import Foundation

/// Scores how well a typed query matches a suggestion name.
public enum Matcher {
    public struct Match: Equatable, Sendable {
        /// Higher is better. Prefix matches always beat substring matches, which beat fuzzy matches.
        public var score: Double
        /// Character offsets in the candidate that matched, for highlighting.
        public var indices: [Int]
        public var isPrefix: Bool = false
    }

    public static let prefixScore: Double = 300
    public static let substringScore: Double = 200

    /// Returns nil when `candidate` does not match `query`.
    public static func match(_ query: String, _ candidate: String, fuzzy: Bool = true) -> Match? {
        if query.isEmpty { return Match(score: 0, indices: [], isPrefix: true) }
        let q = Array(query.lowercased())
        let c = Array(candidate.lowercased())
        guard q.count <= c.count else { return nil }

        if c.starts(with: q) {
            // Shorter candidates first: `git` before `git-lfs` for query `gi`.
            let exact: Double = q.count == c.count ? 50 : 0
            // `-l` before `-L` when you typed `-l`.
            let sameCase: Double = candidate.hasPrefix(query) ? 1 : 0
            // With only `-` or `--` typed, keep the spec's order instead of shortest first.
            let lengthPenalty = query.allSatisfy({ $0 == "-" }) ? 0 : Double(c.count) * 0.01
            return Match(
                score: prefixScore + exact + sameCase - lengthPenalty,
                indices: Array(0..<q.count), isPrefix: true)
        }
        guard fuzzy else { return nil }

        if let range = find(q, in: c) {
            let boundary: Double = isBoundary(c, range) ? 20 : 0
            return Match(
                score: substringScore + boundary - Double(range) * 0.5 - Double(c.count) * 0.01,
                indices: Array(range..<(range + q.count)))
        }

        // Subsequence match, preferring characters at word boundaries. The first
        // character must start a word, so `che` does not match `archive`.
        guard let start = c.indices.first(where: { c[$0] == q[0] && isBoundary(c, $0) }) else { return nil }
        var indices: [Int] = []
        var score: Double = 0
        var qi = 0
        var previous = -2
        for (ci, ch) in c.enumerated() where qi < q.count && ci >= start {
            guard ch == q[qi] else { continue }
            var s: Double = 1
            if ci == previous + 1 { s += 5 }
            if isBoundary(c, ci) { s += 8 }
            if ci == 0 { s += 10 }
            score += s
            indices.append(ci)
            previous = ci
            qi += 1
        }
        guard qi == q.count else { return nil }
        let spread = Double((indices.last ?? 0) - (indices.first ?? 0) - q.count + 1)
        return Match(score: min(score - spread * 0.5, substringScore - 1), indices: indices)
    }

    private static func find(_ needle: [Character], in hay: [Character]) -> Int? {
        guard !needle.isEmpty, needle.count <= hay.count else { return nil }
        for start in 0...(hay.count - needle.count) where hay[start] == needle[0] {
            if Array(hay[start..<(start + needle.count)]) == needle { return start }
        }
        return nil
    }

    private static func isBoundary(_ c: [Character], _ i: Int) -> Bool {
        if i == 0 { return true }
        return "-_./: ".contains(c[i - 1])
    }
}
