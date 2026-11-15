import Foundation

/// Runs generators in the background and caches their results.
///
/// `Engine.complete` asks for cached results; when there are none yet it starts the
/// generator and reports `isLoading`. When the generator finishes, `onUpdate` fires
/// and the caller asks again.
public final class GeneratorRunner: @unchecked Sendable {
    struct Job {
        var key: String
        var generator: Generator
        var spec: String
        var tokens: [String]
        var cwd: String
        /// For template generators with a JavaScript filter: files to filter.
        var templateItems: [Suggestion]?
    }

    private struct Entry {
        var suggestions: [Suggestion]
        var date: Date
        var ttl: TimeInterval
    }

    public static let defaultTTL: TimeInterval = 10
    public static let defaultTimeout: TimeInterval = 5

    let shell: ShellRunner
    weak var store: SpecStore?
    private let lock = NSLock()
    private var cache: [String: Entry] = [:]
    private var running: Set<String> = []
    private let shellQueue = DispatchQueue(label: "zest.generators.shell", attributes: .concurrent)
    private let jsQueue = DispatchQueue(label: "zest.generators.js")
    private lazy var js = JSRuntime(shell: shell)

    /// Run generators inline instead of in the background. Used by tests and the CLI.
    public var synchronous = false
    /// Called on a background queue when a generator finishes.
    public var onUpdate: (@Sendable () -> Void)?

    public init(shell: ShellRunner = ProcessShellRunner()) {
        self.shell = shell
    }

    public func clearCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    /// Cached suggestions, or nil while the generator runs.
    func results(for job: Job) -> [Suggestion]? {
        lock.lock()
        if let entry = cache[job.key], Date().timeIntervalSince(entry.date) < entry.ttl {
            lock.unlock()
            return entry.suggestions
        }
        if running.contains(job.key) {
            lock.unlock()
            return nil
        }
        running.insert(job.key)
        lock.unlock()

        if synchronous {
            finish(job, execute(job))
            return results(for: job)
        }
        let usesJS = job.generator.js != nil
        (usesJS ? jsQueue : shellQueue).async { [weak self] in
            guard let self else { return }
            self.finish(job, self.execute(job))
            self.onUpdate?()
        }
        return nil
    }

    private func finish(_ job: Job, _ suggestions: [Suggestion]) {
        let ttl = job.generator.cache?.ttl ?? Self.defaultTTL
        lock.lock()
        cache[job.key] = Entry(suggestions: suggestions, date: Date(), ttl: ttl)
        running.remove(job.key)
        lock.unlock()
    }

    // MARK: - Execution

    private func execute(_ job: Job) -> [Suggestion] {
        let g = job.generator
        let timeout = g.scriptTimeout ?? Self.defaultTimeout
        guard let store else { return [] }

        if let items = job.templateItems {
            if let index = g.js?.filterTemplateSuggestions,
               let fn = js.function(spec: job.spec, index: index, store: store) {
                return js.filterTemplate(fn, items)
            }
            return items
        }

        if let index = g.js?.custom {
            guard let fn = js.function(spec: job.spec, index: index, store: store) else { return [] }
            return js.custom(fn, tokens: job.tokens, cwd: job.cwd, timeout: timeout)
        }

        var script = g.script
        if let index = g.js?.script, let fn = js.function(spec: job.spec, index: index, store: store) {
            script = js.script(fn, tokens: job.tokens)
        }
        guard let script else { return [] }
        let output = shell.run(script, cwd: job.cwd, timeout: timeout).stdout

        if let index = g.js?.postProcess {
            guard let fn = js.function(spec: job.spec, index: index, store: store) else { return [] }
            return js.postProcess(fn, output: output, tokens: job.tokens)
        }
        return Self.split(output, on: g.splitOn ?? "\n", descriptions: g.descriptionSeparator)
    }

    /// Why a spec's JavaScript companion does not load, or nil.
    func companionError(spec: String) -> String? {
        guard let store else { return nil }
        return jsQueue.sync { js.loadError(spec: spec, store: store) }
    }

    /// The query term for a token when the generator defines `getQueryTerm` as a function.
    func queryTerm(spec: String, generator: Generator, token: String) -> String? {
        guard let index = generator.js?.getQueryTerm, let store else { return nil }
        return jsQueue.sync {
            guard let fn = js.function(spec: spec, index: index, store: store) else { return nil }
            return js.queryTerm(fn, token: token)
        }
    }

    static func split(_ output: String, on separator: String, descriptions: String? = nil) -> [Suggestion] {
        let parts = separator.isEmpty ? [output] : output.components(separatedBy: separator)
        var seen = Set<String>()
        var result: [Suggestion] = []
        for part in parts {
            var name = part.trimmingCharacters(in: .whitespacesAndNewlines)
            var description: String?
            if let descriptions, !descriptions.isEmpty, let range = part.range(of: descriptions) {
                name = part[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let rest = part[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                description = rest.isEmpty ? nil : rest
            }
            guard !name.isEmpty, seen.insert(name).inserted else { continue }
            result.append(Suggestion(name: Names(name), description: description))
        }
        return result
    }
}
