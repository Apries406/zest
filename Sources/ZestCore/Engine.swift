import Foundation

public struct CompletionRequest: Sendable, Equatable {
    public var buffer: String
    /// Cursor position in Unicode scalars, as zsh reports it in `$CURSOR`.
    public var cursor: Int
    public var cwd: String
    /// zsh aliases, e.g. `["g": "git"]`.
    public var aliases: [String: String]
    /// Previous commands, most recent first.
    public var history: [String]

    public init(buffer: String, cursor: Int? = nil, cwd: String, aliases: [String: String] = [:], history: [String] = []) {
        self.buffer = buffer
        self.cursor = cursor ?? buffer.unicodeScalars.count
        self.cwd = cwd
        self.aliases = aliases
        self.history = history
    }
}

public enum CompletionKind: String, Sendable, Codable, Equatable {
    case command, subcommand, option, argument, file, folder, history
}

public struct Completion: Sendable, Equatable {
    public var kind: CompletionKind
    /// The text shown in the popup.
    public var name: String
    /// The text that replaces `replaceStart..<replaceEnd`.
    public var insertText: String
    public var description: String?
    /// The icon from the spec, if any (a Fig icon URL, an emoji or an icon name).
    public var icon: String?
    /// Offsets in `name` that matched the query, for highlighting.
    public var matchedIndices: [Int]
    public var score: Double
    public var appendSpace: Bool
    public var replaceStart: Int
    public var replaceEnd: Int
    public var deprecated: Bool
    /// Key for counting how often this item is picked.
    public var usageKey: String

    public init(
        kind: CompletionKind, name: String, insertText: String, description: String?, icon: String?,
        matchedIndices: [Int], score: Double, appendSpace: Bool, replaceStart: Int, replaceEnd: Int,
        deprecated: Bool, usageKey: String
    ) {
        self.kind = kind
        self.name = name
        self.insertText = insertText
        self.description = description
        self.icon = icon
        self.matchedIndices = matchedIndices
        self.score = score
        self.appendSpace = appendSpace
        self.replaceStart = replaceStart
        self.replaceEnd = replaceEnd
        self.deprecated = deprecated
        self.usageKey = usageKey
    }
}

public struct CompletionResult: Sendable, Equatable {
    public var items: [Completion]
    /// The text being completed.
    public var query: String
    /// A generator is still running; ask again when `GeneratorRunner.onUpdate` fires.
    public var isLoading: Bool
    /// The command path being completed, e.g. `["git", "checkout"]`.
    public var commandPath: [String]

    public static let empty = CompletionResult(items: [], query: "", isLoading: false, commandPath: [])
}

public struct EngineSettings: Sendable, Equatable {
    public var fuzzy = true
    public var historySuggestions = true
    public var maxItems = 100
    /// Suggest executables from `$PATH` at the command position.
    public var pathCommands = true

    public init() {}
}

/// Turns a command line into suggestions.
public final class Engine: @unchecked Sendable {
    public let store: SpecStore
    public let generators: GeneratorRunner
    public let fileSystem: FileSystem
    public var settings: EngineSettings
    public var usage: UsageStore?

    private var pathCache: (date: Date, names: [String])?
    private let pathLock = NSLock()

    public init(
        store: SpecStore, generators: GeneratorRunner = GeneratorRunner(),
        fileSystem: FileSystem = LocalFileSystem(), settings: EngineSettings = EngineSettings(),
        usage: UsageStore? = nil
    ) {
        self.store = store
        self.generators = generators
        self.fileSystem = fileSystem
        self.settings = settings
        self.usage = usage
        generators.store = store
    }

    // MARK: - Entry point

    public func complete(_ request: CompletionRequest) -> CompletionResult {
        let context = Lexer.context(buffer: request.buffer, cursor: request.cursor)
        var collector = Collector(query: context.current.value)

        if context.currentIsRedirectTarget {
            addFiles(token: context.current, foldersOnly: false, request: request, into: &collector)
        } else {
            var words = context.words
            // Skip `FOO=bar` assignments and zsh precommand modifiers.
            while let first = words.first, Self.isAssignment(first.value) || Self.precommands.contains(first.value) {
                words.removeFirst()
            }
            completeCommand(words: words, current: context.current, request: request, into: &collector)
        }

        if settings.historySuggestions {
            addHistory(context: context, request: request, into: &collector)
        }
        return collector.finish(settings: settings, usage: usage)
    }

    /// Applies a completion to the buffer. Returns the new buffer and cursor.
    public static func apply(_ item: Completion, buffer: String, cursor: Int) -> (buffer: String, cursor: Int) {
        let scalars = Array(buffer.unicodeScalars)
        let start = max(0, min(item.replaceStart, scalars.count))
        let end = max(start, min(item.replaceEnd, scalars.count))
        var text = item.insertText
        var cursorInText: Int?
        if let range = text.range(of: "{cursor}") {
            cursorInText = text[..<range.lowerBound].unicodeScalars.count
            text.removeSubrange(range)
        }
        let rest = scalars[end...]
        let nextIsSpace = rest.first == " "
        if item.appendSpace && !nextIsSpace && cursorInText == nil { text += " " }
        var out = String.UnicodeScalarView(scalars[..<start])
        out.append(contentsOf: text.unicodeScalars)
        out.append(contentsOf: rest)
        var newCursor = start + (cursorInText ?? text.unicodeScalars.count)
        if item.appendSpace && nextIsSpace && cursorInText == nil { newCursor += 1 }
        return (String(out), newCursor)
    }

    // MARK: - Walking the command line

    private struct State {
        var node: Subcommand
        var spec: String
        var path: [String]
        var persistent: [Option] = []
        var used: [String: Int] = [:]
        var argIndex = 0
        var argsConsumed = 0
        var pendingArgs: [Arg] = []
        var pendingOption: Option?
        var endOfOptions = false

        var options: [Option] { (node.options ?? []) + persistent }
    }

    private func completeCommand(words: [Token], current: Token, request: CompletionRequest, into c: inout Collector) {
        guard var first = words.first else {
            addCommands(token: current, request: request, into: &c)
            return
        }
        var words = words
        // Expand an alias once: `g ch` with `alias g=git` completes like `git ch`.
        if let alias = request.aliases[first.value] {
            let expanded = Lexer.tokenize(Array(alias.unicodeScalars)).filter { $0.kind == .word }
            if let head = expanded.first, head.value != first.value {
                let mapped = expanded.map { Token(value: $0.value, start: first.start, end: first.end) }
                words = mapped + words.dropFirst()
                first = words[0]
            }
        }

        let name = Self.commandName(first.value)
        guard let spec = store.spec(named: name) else {
            // No spec: still complete paths that are clearly paths.
            let v = current.value
            if v.hasPrefix("/") || v.hasPrefix(".") || v.hasPrefix("~") || v.contains("/") {
                addFiles(token: current, foldersOnly: false, request: request, into: &c)
            }
            return
        }

        var state = State(node: spec, spec: name, path: [name])
        let all = words.map(\.value) + [current.value]
        var i = 1
        while i < words.count {
            let t = words[i].value
            if consume(t, state: &state) {
                i += 1
                continue
            }
            // A positional argument.
            let args = state.node.argList
            if state.argIndex < args.count {
                let arg = args[state.argIndex]
                if arg.isCommand == true || arg.loadSpec != nil {
                    // `sudo git ch`: complete the rest as its own command.
                    completeCommand(words: Array(words[i...]), current: current, request: request, into: &c)
                    return
                }
                if arg.isVariadic != true { state.argIndex += 1 }
            }
            state.argsConsumed += 1
            i += 1
        }

        c.commandPath = state.path
        suggest(for: current, state: state, tokens: all, request: request, into: &c)
    }

    /// Handles subcommands and options. Returns false for a positional argument.
    private func consume(_ t: String, state: inout State) -> Bool {
        if !state.pendingArgs.isEmpty {
            let arg = state.pendingArgs[0]
            let looksLikeOption = t.hasPrefix("-") && t.count > 1
            if (arg.isOptional == true || arg.isVariadic == true) && looksLikeOption {
                state.pendingArgs.removeAll()
                state.pendingOption = nil
            } else {
                if arg.isVariadic != true { state.pendingArgs.removeFirst() }
                if state.pendingArgs.isEmpty { state.pendingOption = nil }
                return true
            }
        }
        if !state.endOfOptions && t == "--" {
            state.endOfOptions = true
            return true
        }
        if !state.endOfOptions && t.hasPrefix("-") && t.count > 1 {
            if let option = findOption(t, in: state.options) {
                markUsed(option, &state)
                if option.separator == nil {
                    state.pendingArgs = option.argList
                    state.pendingOption = option.argList.isEmpty ? nil : option
                }
                return true
            }
            for sep in separators(state) {
                if let range = t.range(of: sep) {
                    let head = String(t[..<range.lowerBound])
                    if let option = findOption(head, in: state.options) {
                        markUsed(option, &state)
                        return true
                    }
                }
            }
            if !t.hasPrefix("--") && state.node.parserDirectives?.flagsArePosixNoncompliant != true {
                // `-abc` is `-a -b -c`; `-ofile` is `-o file`.
                let letters = Array(t.dropFirst())
                for (index, letter) in letters.enumerated() {
                    guard let option = findOption("-" + String(letter), in: state.options) else { break }
                    markUsed(option, &state)
                    if !option.argList.isEmpty {
                        if index == letters.count - 1 {
                            state.pendingArgs = option.argList
                            state.pendingOption = option
                        }
                        break
                    }
                }
            }
            return true
        }
        if state.argsConsumed == 0, !state.endOfOptions,
           let sub = state.node.subcommands?.first(where: { $0.name.all.contains(t) }) {
            enter(sub, state: &state)
            return true
        }
        return false
    }

    private func enter(_ sub: Subcommand, state: inout State) {
        state.persistent += (state.node.options ?? []).filter { $0.isPersistent == true }
        var node = sub
        if let load = sub.loadSpec, let loaded = store.spec(named: load) {
            // The loaded file describes this subcommand; keep its name from the parent.
            node = loaded
            node.name = sub.name
            if node.description == nil { node.description = sub.description }
            state.spec = load
        }
        state.node = node
        state.path.append(sub.name.first)
        state.argIndex = 0
        state.argsConsumed = 0
        state.pendingArgs = []
        state.pendingOption = nil
    }

    private func markUsed(_ option: Option, _ state: inout State) {
        state.used[option.name.first, default: 0] += 1
    }

    private func findOption(_ name: String, in options: [Option]) -> Option? {
        options.first { $0.name.all.contains(name) }
    }

    private func separators(_ state: State) -> [String] {
        state.node.parserDirectives?.optionArgSeparators?.values ?? ["="]
    }

    // MARK: - Suggestions for the current word

    private func suggest(for token: Token, state: State, tokens: [String], request: CompletionRequest, into c: inout Collector) {
        let query = token.value
        let usagePrefix = state.path.joined(separator: " ")

        if let option = state.pendingOption, let arg = state.pendingArgs.first {
            addArg(arg, token: token, state: state, tokens: tokens, request: request, usagePrefix: usagePrefix + " " + option.name.first, into: &c)
            if arg.isOptional != true { return }
        }

        let wantsOptions = !state.endOfOptions && query.hasPrefix("-")
        if wantsOptions {
            // `--format=sh`: complete the value after the separator.
            for sep in separators(state) where query.hasPrefix("-") {
                guard let range = query.range(of: sep) else { continue }
                let head = String(query[..<range.lowerBound])
                guard let option = findOption(head, in: state.options), let arg = option.argList.first else { continue }
                let headLength = query[..<range.upperBound].unicodeScalars.count
                var valueToken = token
                valueToken.value = String(query[range.upperBound...])
                valueToken.start = token.start + headLength
                c.query = valueToken.value
                addArg(arg, token: valueToken, state: state, tokens: tokens, request: request, usagePrefix: usagePrefix + " " + head, into: &c)
                return
            }
            addOptions(state: state, token: token, usagePrefix: usagePrefix, into: &c)
        }

        let args = state.node.argList
        let currentArg: Arg? = state.argIndex < args.count ? args[state.argIndex] : nil
        let before = c.items.count

        if !wantsOptions || currentArg != nil {
            if state.argsConsumed == 0 && !state.endOfOptions {
                for sub in state.node.subcommands ?? [] {
                    c.add(
                        kind: .subcommand, names: sub.name.all, display: sub.displayName,
                        insert: sub.insertValue, description: sub.description, icon: sub.icon,
                        priority: sub.priority, hidden: sub.hidden, deprecated: sub.deprecated,
                        token: token, appendSpace: sub.insertValue == nil, usageKey: usagePrefix,
                        filter: sub.filterStrategy ?? state.node.filterStrategy, settings: settings)
                }
            }
            if let arg = currentArg {
                if arg.isCommand == true || arg.loadSpec != nil {
                    addCommands(token: token, request: request, into: &c)
                } else {
                    addArg(arg, token: token, state: state, tokens: tokens, request: request, usagePrefix: usagePrefix, into: &c)
                }
            }
            for s in state.node.additionalSuggestions ?? [] {
                addSuggestion(s, kind: .argument, token: token, usagePrefix: usagePrefix, into: &c)
            }
        }

        // With nothing else to offer, show the options.
        if !wantsOptions && c.items.count == before && query.isEmpty && !state.endOfOptions && state.pendingArgs.isEmpty {
            addOptions(state: state, token: token, usagePrefix: usagePrefix, into: &c)
        }
    }

    private func addOptions(state: State, token: Token, usagePrefix: String, into c: inout Collector) {
        let usedNames = Set(state.used.keys)
        for option in state.options {
            let count = state.used[option.name.first] ?? 0
            if count > 0 && !(option.isRepeatable ?? .no).allows(count: count) { continue }
            if let exclusive = option.exclusiveOn, exclusive.contains(where: { name in
                usedNames.contains(where: { used in self.findOption(used, in: state.options)?.name.all.contains(name) == true })
            }) { continue }
            var appendSpace = option.insertValue == nil
            var insertSuffix = ""
            if let sep = option.separator, !option.argList.isEmpty {
                insertSuffix = sep
                appendSpace = false
            }
            c.addOption(
                option, token: token, insertSuffix: insertSuffix, appendSpace: appendSpace,
                usageKey: usagePrefix, filter: state.node.filterStrategy, settings: settings)
        }
    }

    private func addArg(
        _ arg: Arg, token: Token, state: State, tokens: [String], request: CompletionRequest,
        usagePrefix: String, into c: inout Collector
    ) {
        for s in arg.suggestions ?? [] {
            addSuggestion(s, kind: .argument, token: token, usagePrefix: usagePrefix, filter: arg.filterStrategy, into: &c)
        }
        if arg.isScript == true {
            addFiles(token: token, foldersOnly: false, request: request, into: &c)
        }
        let templates = arg.template?.values ?? []
        if templates.contains(.filepaths) {
            addFiles(token: token, foldersOnly: false, request: request, into: &c)
        } else if templates.contains(.folders) {
            addFiles(token: token, foldersOnly: true, request: request, into: &c)
        }
        for generator in arg.generators?.values ?? [] {
            addGenerator(generator, token: token, state: state, tokens: tokens, request: request, usagePrefix: usagePrefix, into: &c)
        }
    }

    private func addGenerator(
        _ g: Generator, token: Token, state: State, tokens: [String], request: CompletionRequest,
        usagePrefix: String, into c: inout Collector
    ) {
        let templates = g.template?.values ?? []
        let hasScript = g.script != nil || g.js?.script != nil || g.js?.custom != nil

        // Generators can complete only the part after a character such as `/` or `,`.
        var itemToken = token
        if let term = g.getQueryTerm, let range = token.value.range(of: term, options: .backwards) {
            itemToken.value = String(token.value[range.upperBound...])
            itemToken.start = token.start + token.value[..<range.upperBound].unicodeScalars.count
        } else if g.js?.getQueryTerm != nil,
                  let term = generators.queryTerm(spec: state.spec, generator: g, token: token.value),
                  token.value.hasSuffix(term) {
            itemToken.value = term
            itemToken.start = token.start + token.value.unicodeScalars.count - term.unicodeScalars.count
        }

        if !templates.isEmpty && !hasScript {
            if g.js?.filterTemplateSuggestions != nil {
                let files = fileItems(token: token, foldersOnly: !templates.contains(.filepaths), cwd: request.cwd)
                let key = "template|\(state.spec)|\(files.dir)|\(g.js?.filterTemplateSuggestions ?? 0)"
                let job = GeneratorRunner.Job(
                    key: key, generator: g, spec: state.spec, tokens: tokens, cwd: request.cwd,
                    templateItems: files.entries.map {
                        var s = Suggestion(name: Names($0.name + ($0.isDirectory ? "/" : "")))
                        s.type = $0.isDirectory ? "folder" : "file"
                        return s
                    })
                if let filtered = generators.results(for: job) {
                    let allowed = Set(filtered.map { $0.name.first })
                    addFiles(token: token, foldersOnly: !templates.contains(.filepaths), request: request, into: &c) {
                        allowed.contains($0)
                    }
                } else {
                    c.isLoading = true
                }
            } else if let filter = g.filter {
                addFiles(token: token, foldersOnly: !templates.contains(.filepaths), request: request, into: &c) {
                    filter.accepts($0, isDirectory: $0.hasSuffix("/"))
                }
            } else {
                addFiles(token: token, foldersOnly: !templates.contains(.filepaths), request: request, into: &c)
            }
            return
        }
        guard hasScript else { return }

        // Re-run when the text before the trigger character changes, e.g. a new folder after `/`.
        var triggerPart = ""
        if let trigger = g.trigger, let range = token.value.range(of: trigger, options: .backwards) {
            triggerPart = String(token.value[..<range.lowerBound])
        }
        let usesTokens = g.js?.script != nil || g.js?.custom != nil
        let identity = (try? String(decoding: JSONEncoder().encode(g), as: UTF8.self)) ?? ""
        var key = "\(state.spec)|\(identity)|\(request.cwd)|\(triggerPart)"
        if usesTokens { key += "|" + tokens.dropLast().joined(separator: "\u{1f}") }
        let job = GeneratorRunner.Job(key: key, generator: g, spec: state.spec, tokens: tokens, cwd: request.cwd)
        guard let results = generators.results(for: job) else {
            c.isLoading = true
            return
        }
        for s in results {
            var item = s
            if item.type == "folder" || item.type == "file" {
                let isDir = item.type == "folder"
                c.add(
                    kind: isDir ? .folder : .file, names: item.name.all, display: item.displayName,
                    insert: item.insertValue, description: item.description, icon: item.icon,
                    priority: item.priority, hidden: item.hidden, deprecated: item.deprecated,
                    token: itemToken, appendSpace: !isDir && item.insertValue == nil,
                    usageKey: usagePrefix, filter: nil, settings: settings, escape: true)
                continue
            }
            if item.insertValue == nil && token.openQuote == nil {
                let escaped = item.name.first.shellEscaped()
                if escaped != item.name.first { item.insertValue = escaped }
            }
            addSuggestion(item, kind: .argument, token: itemToken, usagePrefix: usagePrefix, into: &c)
        }
    }

    private func addSuggestion(
        _ s: Suggestion, kind: CompletionKind, token: Token, usagePrefix: String,
        filter: FilterStrategy? = nil, into c: inout Collector
    ) {
        c.add(
            kind: kind, names: s.name.all, display: s.displayName, insert: s.insertValue,
            description: s.description, icon: s.icon ?? s.type.map { "type:" + $0 },
            priority: s.priority, hidden: s.hidden, deprecated: s.deprecated, token: token,
            appendSpace: s.insertValue == nil || s.insertValue?.hasSuffix(" ") == false && s.insertValue?.contains("{cursor}") == false,
            usageKey: usagePrefix, filter: filter, settings: settings)
    }

    // MARK: - Commands

    private func addCommands(token: Token, request: CompletionRequest, into c: inout Collector) {
        // Typed in the wrong keyboard layout: suggest the command it was meant to be.
        if let converted = Self.switchLayout(token.value), !converted.isEmpty {
            var latin = token
            latin.value = converted
            let names = Set(store.commands().keys).union(request.aliases.keys).union(Self.zshBuiltins)
                .union(settings.pathCommands ? pathCommandSet() : [])
            for name in names.filter({ $0.hasPrefix(converted) }).sorted(by: { $0.count < $1.count || ($0.count == $1.count && $0 < $1) }).prefix(5) {
                c.add(
                    kind: .command, names: [name], display: nil, insert: nil,
                    description: "Keyboard layout: \(token.value) → \(name)", icon: store.commands()[name]?.icon,
                    priority: 90, hidden: nil, deprecated: nil, token: latin, appendSpace: true,
                    usageKey: "", filter: .prefix, settings: settings)
            }
        }
        var seen = Set<String>()
        let used = Self.commandCounts(request.history)
        // Commands you run often come first: `n` suggests npm before nc or ng.
        func bonus(_ name: String) -> Double {
            guard let count = used[name] else { return 0 }
            return min(60, log2(Double(count) + 1) * 15)
        }
        for (name, info) in store.commands().sorted(by: { $0.key < $1.key }) {
            seen.insert(name)
            c.add(
                kind: .command, names: [name], display: nil, insert: nil, description: info.description,
                icon: info.icon, priority: 55, hidden: nil, deprecated: nil, token: token,
                appendSpace: true, usageKey: "", filter: nil, settings: settings, bonus: bonus(name))
        }
        for (alias, expansion) in request.aliases.sorted(by: { $0.key < $1.key }) where !seen.contains(alias) {
            seen.insert(alias)
            c.add(
                kind: .command, names: [alias], display: nil, insert: nil, description: "alias: \(expansion)",
                icon: nil, priority: 50, hidden: nil, deprecated: nil, token: token,
                appendSpace: true, usageKey: "", filter: nil, settings: settings, bonus: bonus(alias))
        }
        // Executables on PATH only once something is typed; there are thousands.
        guard settings.pathCommands, !token.value.isEmpty else { return }
        for name in pathCommands() where !seen.contains(name) {
            seen.insert(name)
            c.add(
                kind: .command, names: [name], display: nil, insert: nil, description: nil, icon: nil,
                priority: 40, hidden: nil, deprecated: nil, token: token, appendSpace: true,
                usageKey: "", filter: .prefix, settings: settings, bonus: bonus(name))
        }
    }

    private func pathCommands() -> [String] {
        pathLock.lock()
        defer { pathLock.unlock() }
        if let cache = pathCache, Date().timeIntervalSince(cache.date) < 60 { return cache.names }
        let path = ProcessShellRunner.searchPath(ProcessInfo.processInfo.environment["PATH"])
        var names = Set<String>()
        for dir in path.split(separator: ":") {
            for entry in fileSystem.list(String(dir)) where !entry.isDirectory && !entry.name.hasPrefix(".") {
                names.insert(entry.name)
            }
        }
        let sorted = names.sorted()
        pathCache = (Date(), sorted)
        return sorted
    }

    // MARK: - Files

    private struct FileListing {
        var dir: String
        var entries: [FileEntry]
    }

    private func fileItems(token: Token, foldersOnly: Bool, cwd: String) -> FileListing {
        let value = token.value
        let slash = value.range(of: "/", options: .backwards)
        let dirPart = slash.map { String(value[..<$0.upperBound]) } ?? ""
        var dir: String
        if dirPart.hasPrefix("~") {
            dir = fileSystem.homeDirectory + String(dirPart.dropFirst())
        } else if dirPart.hasPrefix("/") {
            dir = dirPart
        } else {
            dir = (cwd as NSString).appendingPathComponent(dirPart)
        }
        dir = (dir as NSString).standardizingPath
        if dir.isEmpty { dir = "/" }
        var entries = fileSystem.list(dir)
        if foldersOnly { entries = entries.filter(\.isDirectory) }
        return FileListing(dir: dir, entries: entries)
    }

    private func addFiles(
        token: Token, foldersOnly: Bool, request: CompletionRequest, into c: inout Collector,
        include: ((String) -> Bool)? = nil
    ) {
        let value = token.value
        let base = value.range(of: "/", options: .backwards).map { String(value[$0.upperBound...]) } ?? value
        var baseToken = token
        baseToken.value = base
        // The folder part stays as typed; only the name after the last `/` is replaced.
        baseToken.start = fileNameStart(token, buffer: request.buffer)
        let listing = fileItems(token: token, foldersOnly: foldersOnly, cwd: request.cwd)
        let showHidden = base.hasPrefix(".")
        let sorted = listing.entries.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        for entry in sorted {
            if entry.name.hasPrefix(".") && !showHidden { continue }
            let display = entry.name + (entry.isDirectory ? "/" : "")
            if let include, !include(display) { continue }
            c.add(
                kind: entry.isDirectory ? .folder : .file, names: [display], display: nil,
                insert: entry.name.shellEscaped(inQuote: token.openQuote) + (entry.isDirectory ? "/" : ""),
                description: nil, icon: nil, priority: nil, hidden: nil, deprecated: nil, token: baseToken,
                appendSpace: !entry.isDirectory, usageKey: "",
                filter: showHidden ? .prefix : nil, settings: settings)
        }
    }

    /// Where the file name starts in the raw buffer: after the last `/` or an open quote.
    /// The raw text may contain quotes and backslashes, so the token value can't be used.
    private func fileNameStart(_ token: Token, buffer: String) -> Int {
        let scalars = Array(buffer.unicodeScalars)
        let end = min(token.end, scalars.count)
        guard token.start < end else { return token.start }
        var start = token.start
        for i in token.start..<end {
            let ch = scalars[i]
            if ch == "/" { start = i + 1 }
            if let quote = token.openQuote, Character(ch) == quote { start = max(start, i + 1) }
        }
        return start
    }

    // MARK: - History

    private func addHistory(context: CommandContext, request: CompletionRequest, into c: inout Collector) {
        let scalars = Array(request.buffer.unicodeScalars)
        let cursor = max(0, min(request.cursor, scalars.count))
        guard context.commandStart <= cursor else { return }
        let typed = String(String.UnicodeScalarView(scalars[context.commandStart..<cursor]))
        let trimmed = typed.drop(while: { $0 == " " })
        guard trimmed.count >= 2 else { return }
        let leading = typed.count - trimmed.count
        var seen = Set<String>()
        var added = 0
        for entry in request.history where added < 3 {
            guard entry.hasPrefix(trimmed), entry != String(trimmed), !entry.contains("\n"),
                  seen.insert(entry).inserted, commandExists(in: entry, request: request) else { continue }
            c.items.append(Completion(
                kind: .history, name: entry, insertText: entry, description: nil, icon: nil,
                matchedIndices: Array(0..<trimmed.count), score: -1000 - Double(added),
                appendSpace: false, replaceStart: context.commandStart + leading,
                replaceEnd: context.current.end, deprecated: false, usageKey: ""))
            added += 1
        }
    }

    /// False for history entries that failed because the command does not exist,
    /// e.g. `св ю` typed with the wrong keyboard layout.
    private func commandExists(in line: String, request: CompletionRequest) -> Bool {
        let words = Lexer.tokenize(Array(line.unicodeScalars)).filter { $0.kind == .word }.map(\.value)
        guard let first = words.first(where: { !Self.isAssignment($0) && !Self.precommands.contains($0) }) else { return true }
        if first.contains("/") || first.hasPrefix("$") || first.hasPrefix("~") { return true }
        if Self.zshBuiltins.contains(first) || request.aliases[first] != nil || store.commands()[first] != nil {
            return true
        }
        return pathCommandSet().contains(first)
    }

    private var pathSet: (date: Date, names: Set<String>)?

    private func pathCommandSet() -> Set<String> {
        if let cache = pathSet, Date().timeIntervalSince(cache.date) < 60 { return cache.names }
        let names = Set(pathCommands())
        pathSet = (Date(), names)
        return names
    }


    /// How often each command starts a line in the history.
    static func commandCounts(_ history: [String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for line in history {
            let first = line.prefix { $0 != " " && $0 != "\t" }
            if !first.isEmpty { counts[String(first), default: 0] += 1 }
        }
        return counts
    }

    static let zshBuiltins: Set<String> = [
        "alias", "autoload", "bg", "bindkey", "break", "builtin", "cd", "chdir", "command", "continue",
        "declare", "dirs", "disown", "echo", "emulate", "eval", "exec", "exit", "export", "false", "fc",
        "fg", "functions", "getopts", "hash", "history", "jobs", "kill", "let", "local", "logout",
        "popd", "print", "printf", "pushd", "pwd", "read", "readonly", "rehash", "return", "set",
        "setopt", "shift", "source", "suspend", "test", "time", "trap", "true", "type", "typeset",
        "ulimit", "umask", "unalias", "unfunction", "unhash", "unset", "unsetopt", "wait", "whence",
        "where", "which", "zle", "zmodload", "zstyle", ".", "[", "[[",
    ]

    /// Russian and Ukrainian ЙЦУКЕН keys mapped to the US keys at the same place.
    static let layoutMap: [Character: Character] = {
        let cyrillic = Array("йцукенгшщзхъфывапролджэячсмитьбюёіїєґ")
        let latin = Array("qwertyuiop[]asdfghjkl;'zxcvbnm,.`s]'`")
        var map: [Character: Character] = [:]
        for (c, l) in zip(cyrillic, latin) {
            map[c] = l
            if let upper = String(c).uppercased().first { map[upper] = Character(String(l).uppercased()) }
        }
        return map
    }()

    /// `св` typed with a Cyrillic layout is `cd`. Returns nil if the word has no Cyrillic letters.
    static func switchLayout(_ word: String) -> String? {
        guard word.contains(where: { layoutMap[$0] != nil }) else { return nil }
        let converted = String(word.map { layoutMap[$0] ?? $0 })
        return converted.allSatisfy({ $0.isASCII }) ? converted : nil
    }

    // MARK: - Helpers

    static let precommands: Set<String> = ["noglob", "nocorrect", "builtin", "command", "exec", "-"]

    static func isAssignment(_ word: String) -> Bool {
        guard let eq = word.firstIndex(of: "="), eq != word.startIndex else { return false }
        return word[..<eq].allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// `./script.sh` and `/usr/bin/git` use the spec of their file name.
    static func commandName(_ word: String) -> String {
        if word.contains("/") {
            return (word as NSString).lastPathComponent
        }
        return word
    }
}
