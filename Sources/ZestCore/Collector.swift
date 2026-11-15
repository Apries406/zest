import Foundation

/// Gathers, scores and sorts suggestions for one request.
struct Collector {
    var query: String
    var items: [Completion] = []
    var isLoading = false
    var commandPath: [String] = []

    init(query: String) {
        self.query = query
    }

    // swiftlint:disable:next function_parameter_count
    mutating func add(
        kind: CompletionKind, names: [String], display: String?, insert: String?,
        description: String?, icon: String?, priority: Double?, hidden: Bool?, deprecated: Bool?,
        token: Token, appendSpace: Bool, usageKey: String, filter: FilterStrategy?,
        settings: EngineSettings, escape: Bool = false, bonus: Double = 0
    ) {
        let query = token.value
        let fuzzy = filter == .prefix ? false : settings.fuzzy
        guard let primary = names.first, !primary.isEmpty,
              let (name, match) = best(names, query: query, fuzzy: fuzzy) else { return }
        if hidden == true && !(match.isPrefix && query.count >= 2) { return }

        var score = match.score + ((priority ?? 50) - 50) * 3 + bonus
        if deprecated == true { score -= 5 }
        // Aliases match too, but the popup shows and inserts the main name.
        let shown = display ?? primary
        items.append(Completion(
            kind: kind, name: shown,
            insertText: Self.clean(insert ?? (escape ? primary.shellEscaped(inQuote: token.openQuote) : primary)),
            description: description, icon: icon,
            matchedIndices: display == nil && name == primary ? match.indices : [],
            score: score, appendSpace: appendSpace,
            replaceStart: token.start, replaceEnd: token.end,
            deprecated: deprecated == true, usageKey: usageKey + "|" + primary))
    }

    mutating func addOption(
        _ option: Option, token: Token, insertSuffix: String, appendSpace: Bool,
        usageKey: String, filter: FilterStrategy?, settings: EngineSettings
    ) {
        let query = token.value
        var candidates = option.name.all
        if query.hasPrefix("--") { candidates = candidates.filter { $0.hasPrefix("--") } }
        let fuzzy = filter == .prefix ? false : settings.fuzzy
        guard let (name, match) = best(candidates, query: query, fuzzy: fuzzy) else { return }
        if option.hidden == true && !(match.isPrefix && query.count >= 2) { return }

        // Show every alias, e.g. `-b, --branch`, and highlight the one that matched.
        let all = option.name.all
        let shown = option.displayName ?? all.joined(separator: ", ")
        var indices: [Int] = []
        if option.displayName == nil, let position = all.firstIndex(of: name) {
            let offset = all[..<position].reduce(0) { $0 + $1.count + 2 }
            indices = match.indices.map { $0 + offset }
        }
        var score = match.score + ((option.priority ?? 50) - 50) * 3
        if option.deprecated == true { score -= 5 }
        if option.isRequired == true { score += 10 }
        items.append(Completion(
            kind: .option, name: shown, insertText: Self.clean(option.insertValue ?? (name + insertSuffix)),
            description: option.description, icon: option.icon, matchedIndices: indices,
            score: score, appendSpace: appendSpace, replaceStart: token.start, replaceEnd: token.end,
            deprecated: option.deprecated == true, usageKey: usageKey + "|" + all[0]))
    }

    /// Fig used a trailing newline in `insertValue` to run the command right away; zest
    /// never runs anything, so newlines and other control characters are dropped.
    static func clean(_ text: String) -> String {
        guard text.contains(where: { $0.isNewline || ($0.asciiValue.map { $0 < 32 } ?? false) }) else { return text }
        return String(text.filter { !$0.isNewline && !($0.asciiValue.map { $0 < 32 } ?? false) })
    }

    private func best(_ names: [String], query: String, fuzzy: Bool) -> (String, Matcher.Match)? {
        var result: (String, Matcher.Match)?
        for name in names {
            guard let m = Matcher.match(query, name, fuzzy: fuzzy) else { continue }
            if result == nil || m.score > result!.1.score { result = (name, m) }
        }
        return result
    }

    func finish(settings: EngineSettings, usage: UsageStore?) -> CompletionResult {
        var scored = items
        if let usage {
            for i in scored.indices where scored[i].kind != .history {
                scored[i].score += usage.boost(scored[i].usageKey)
            }
        }
        // Stable sort: equal scores keep the order of the spec.
        let ordered = scored.enumerated().sorted {
            $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset
        }.map(\.element)

        var seen = Set<String>()
        var unique: [Completion] = []
        for item in ordered {
            let key = "\(item.replaceStart)|\(item.insertText)"
            guard seen.insert(key).inserted else { continue }
            unique.append(item)
            if unique.count >= settings.maxItems { break }
        }
        return CompletionResult(items: unique, query: query, isLoading: isLoading, commandPath: commandPath)
    }
}
