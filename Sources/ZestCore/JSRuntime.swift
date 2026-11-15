import Foundation
import JavaScriptCore

/// Runs the JavaScript functions of specs imported from Fig.
///
/// The Fig importer writes each spec's functions into a companion `<spec>.js` file.
/// The file defines `__zestSpec`; its functions are numbered in the order of a
/// depth-first walk (see `collectScript`), and generators refer to them by number.
/// Not thread-safe: use from one serial queue.
final class JSRuntime {
    private let shell: ShellRunner
    private var modules: [String: [JSValue]] = [:]
    private var failed: Set<String> = []
    private let vm = JSVirtualMachine()

    /// Must match `collectFunctions` in tools/import-fig/import.mjs.
    static let collectScript = """
    function __zestCollect(root) {
      const out = [];
      const seen = new Set();
      (function walk(v) {
        if (typeof v === 'function') { if (!seen.has(v)) { seen.add(v); out.push(v); } return; }
        if (v === null || typeof v !== 'object' || seen.has(v)) return;
        seen.add(v);
        if (Array.isArray(v)) { for (const x of v) walk(x); return; }
        for (const k of Object.keys(v)) walk(v[k]);
      })(root);
      return out;
    }
    """

    init(shell: ShellRunner) {
        self.shell = shell
    }

    func function(spec: String, index: Int, store: SpecStore) -> JSValue? {
        if let list = modules[spec] { return index < list.count ? list[index] : nil }
        if failed.contains(spec) { return nil }
        guard let url = store.companionScript(for: spec),
              let source = try? String(contentsOf: url, encoding: .utf8),
              let context = JSContext(virtualMachine: vm)
        else {
            failed.insert(spec)
            return nil
        }
        install(in: context)
        context.evaluateScript(Self.collectScript)
        context.evaluateScript(source, withSourceURL: url)
        guard context.exception == nil,
              let spec_ = context.objectForKeyedSubscript("__zestSpec"), !spec_.isUndefined,
              let list = context.objectForKeyedSubscript("__zestCollect")?.call(withArguments: [spec_]),
              let count = list.objectForKeyedSubscript("length")?.toInt32()
        else {
            failed.insert(spec)
            return nil
        }
        var functions: [JSValue] = []
        for i in 0..<Int(count) {
            if let f = list.atIndex(i) { functions.append(f) }
        }
        modules[spec] = functions
        return index < functions.count ? functions[index] : nil
    }

    // MARK: - Calls

    /// Fig `script` functions return a string, an argv array or `{command, args}`.
    func script(_ fn: JSValue, tokens: [String]) -> Script? {
        guard let value = fn.call(withArguments: [tokens]), !value.isUndefined, !value.isNull else { return nil }
        if value.isString { return .shell(value.toString()) }
        if value.isArray, let list = value.toArray() as? [String] { return .argv(list) }
        if value.isObject, let command = value.objectForKeyedSubscript("command")?.toString() {
            let args = value.objectForKeyedSubscript("args")?.toArray() as? [String] ?? []
            return .argv([command] + args)
        }
        return nil
    }

    func postProcess(_ fn: JSValue, output: String, tokens: [String]) -> [Suggestion] {
        guard let value = fn.call(withArguments: [output, tokens]) else { return [] }
        return suggestions(from: value)
    }

    func custom(_ fn: JSValue, tokens: [String], cwd: String, timeout: TimeInterval) -> [Suggestion] {
        guard let context = fn.context else { return [] }
        let shell = self.shell
        // Old Fig API: executeShellCommand("cmd") -> Promise<string>.
        // New Fig API: executeShellCommand({command, args, cwd}) -> Promise<{stdout, stderr, status}>.
        let execute: @convention(block) (JSValue) -> JSValue = { arg in
            let ctx = JSContext.current()!
            if arg.isString {
                let result = shell.run(.shell(arg.toString()), cwd: cwd, timeout: timeout)
                return Self.resolved(ctx, JSValue(object: result.stdout, in: ctx))
            }
            let command = arg.objectForKeyedSubscript("command")?.toString() ?? ""
            let args = arg.objectForKeyedSubscript("args")?.toArray() as? [String] ?? []
            var dir = cwd
            if let c = arg.objectForKeyedSubscript("cwd"), c.isString { dir = c.toString() }
            let result = shell.run(.argv([command] + args), cwd: dir, timeout: timeout)
            let object: [String: Any] = ["stdout": result.stdout, "stderr": result.stderr, "status": Int(result.status)]
            return Self.resolved(ctx, JSValue(object: object, in: ctx))
        }
        let generatorContext: [String: Any] = [
            "currentWorkingDirectory": cwd,
            "searchTerm": tokens.last ?? "",
            "environmentVariables": [String: String](),
            "sshPrefix": "",
            "currentProcess": "zsh",
        ]
        let executeValue = JSValue(object: execute, in: context)
        guard let promise = fn.call(withArguments: [tokens, executeValue as Any, generatorContext]) else { return [] }
        return awaitValue(promise, in: context).map(suggestions(from:)) ?? []
    }

    func queryTerm(_ fn: JSValue, token: String) -> String? {
        guard let value = fn.call(withArguments: [token]), value.isString else { return nil }
        return value.toString()
    }

    func filterTemplate(_ fn: JSValue, _ items: [Suggestion]) -> [Suggestion] {
        let objects: [[String: Any]] = items.map {
            ["name": $0.name.first, "type": $0.type ?? "file", "insertValue": $0.insertValue ?? $0.name.first]
        }
        guard let value = fn.call(withArguments: [objects]) else { return items }
        return suggestions(from: value)
    }

    // MARK: - Helpers

    private static func resolved(_ ctx: JSContext, _ value: JSValue?) -> JSValue {
        let promise = ctx.objectForKeyedSubscript("Promise")!
        return promise.invokeMethod("resolve", withArguments: [value as Any])
    }

    /// Waits for a promise. JavaScriptCore runs pending promise jobs when control
    /// returns from a call, and our `executeShellCommand` resolves synchronously.
    private func awaitValue(_ value: JSValue, in context: JSContext) -> JSValue? {
        guard value.isObject, let then = value.objectForKeyedSubscript("then"), !then.isUndefined else {
            return value
        }
        let box = ResultBox()
        let onResolve: @convention(block) (JSValue) -> Void = { box.value = $0 }
        let onReject: @convention(block) (JSValue) -> Void = { _ in box.rejected = true }
        value.invokeMethod("then", withArguments: [
            JSValue(object: onResolve, in: context) as Any,
            JSValue(object: onReject, in: context) as Any,
        ])
        // Flush the job queue in case it has not run yet.
        context.evaluateScript("void 0")
        return box.rejected ? nil : box.value
    }

    func suggestions(from value: JSValue) -> [Suggestion] {
        guard value.isArray, let count = value.objectForKeyedSubscript("length")?.toInt32() else { return [] }
        var out: [Suggestion] = []
        for i in 0..<Int(count) {
            guard let item = value.atIndex(i) else { continue }
            if item.isString {
                out.append(Suggestion(name: Names(item.toString())))
                continue
            }
            guard item.isObject, let nameValue = item.objectForKeyedSubscript("name"), !nameValue.isUndefined else { continue }
            let names: [String]
            if nameValue.isArray {
                names = (nameValue.toArray() ?? []).compactMap { $0 as? String }
            } else {
                names = [nameValue.toString()]
            }
            guard !names.isEmpty else { continue }
            var s = Suggestion(name: Names(names))
            s.description = string(item, "description")
            s.displayName = string(item, "displayName")
            s.insertValue = string(item, "insertValue")
            s.icon = string(item, "icon")
            s.type = string(item, "type")
            if let p = item.objectForKeyedSubscript("priority"), p.isNumber { s.priority = p.toDouble() }
            if let h = item.objectForKeyedSubscript("hidden"), h.isBoolean { s.hidden = h.toBool() }
            out.append(s)
        }
        return out
    }

    private func string(_ object: JSValue, _ key: String) -> String? {
        guard let v = object.objectForKeyedSubscript(key), v.isString else { return nil }
        return v.toString()
    }

    private func install(in context: JSContext) {
        let log: @convention(block) () -> Void = {}
        let console = JSValue(newObjectIn: context)
        console?.setObject(log, forKeyedSubscript: "log" as NSString)
        console?.setObject(log, forKeyedSubscript: "error" as NSString)
        console?.setObject(log, forKeyedSubscript: "warn" as NSString)
        context.setObject(console, forKeyedSubscript: "console" as NSString)
    }
}

private final class ResultBox {
    var value: JSValue?
    var rejected = false
}
