import Foundation
import Yams

/// Finds mistakes in spec files that decoding alone would not report, such as a
/// misspelled field name (`descripton`) that would otherwise be ignored silently.
public enum SpecLinter {
    static let common: Set<String> = ["name", "displayName", "description", "icon", "priority", "hidden", "deprecated", "insertValue"]
    static let subcommandKeys = common.union([
        "subcommands", "options", "args", "loadSpec", "requiresSubcommand", "filterStrategy",
        "parserDirectives", "additionalSuggestions",
    ])
    static let optionKeys = common.union([
        "args", "isRepeatable", "isPersistent", "isRequired", "requiresSeparator", "exclusiveOn", "dependsOn",
    ])
    static let argKeys: Set<String> = [
        "name", "description", "isOptional", "isVariadic", "optionsCanBreakVariadicArg", "isCommand",
        "isScript", "template", "suggestions", "generators", "default", "filterStrategy", "loadSpec",
        "suggestCurrentToken",
    ]
    static let suggestionKeys = common.union(["type"])
    static let generatorKeys: Set<String> = [
        "script", "splitOn", "descriptionSeparator", "template", "filter", "cache", "scriptTimeout", "trigger", "getQueryTerm", "js",
    ]

    public static func lint(url: URL) -> [String] {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            return ["cannot read the file: \(error.localizedDescription)"]
        }
        return lint(yaml: text, companionExists: FileManager.default.fileExists(
            atPath: url.deletingPathExtension().appendingPathExtension("js").path))
    }

    public static func lint(yaml text: String, companionExists: Bool = false) -> [String] {
        var issues: [String] = []
        do {
            _ = try YAMLDecoder().decode(Spec.self, from: text)
        } catch {
            return [SpecStore.describe(error)]
        }
        guard let root = try? Yams.load(yaml: text) else { return ["not valid YAML"] }
        var usesJS = false
        subcommand(root, path: "", issues: &issues, usesJS: &usesJS)
        if usesJS && !companionExists {
            issues.append("generators use `js`, but the companion .js file is missing")
        }
        return issues
    }

    private static func check(_ node: Any, keys: Set<String>, path: String, issues: inout [String]) -> [String: Any]? {
        guard let dict = node as? [String: Any] else { return nil }
        for key in dict.keys.sorted() where !keys.contains(key) {
            let hint = keys.min(by: { distance($0, key) < distance($1, key) }).flatMap { distance($0, key) <= 3 ? " (did you mean `\($0)`?)" : nil } ?? ""
            issues.append("\(path.isEmpty ? "" : path + ".")\(key): unknown field\(hint)")
        }
        if keys.contains("name") && keys != argKeys {
            if let name = dict["name"] as? String, name.isEmpty { issues.append("\(path).name: empty") }
        }
        return dict
    }

    private static func label(_ dict: [String: Any]) -> String {
        if let s = dict["name"] as? String { return s }
        if let a = dict["name"] as? [Any], let s = a.first as? String { return s }
        return "?"
    }

    private static func subcommand(_ node: Any, path: String, issues: inout [String], usesJS: inout Bool) {
        guard let dict = check(node, keys: subcommandKeys, path: path, issues: &issues) else { return }
        var seen = Set<String>()
        for case let sub as [String: Any] in dict["subcommands"] as? [Any] ?? [] {
            let name = label(sub)
            if !seen.insert(name).inserted { issues.append("\(path)subcommands.\(name): defined twice") }
            subcommand(sub, path: path + "subcommands.\(name).", issues: &issues, usesJS: &usesJS)
        }
        for case let opt as [String: Any] in dict["options"] as? [Any] ?? [] {
            let p = path + "options.\(label(opt))"
            _ = check(opt, keys: optionKeys, path: p, issues: &issues)
            args(opt["args"], path: p + ".args", issues: &issues, usesJS: &usesJS)
        }
        args(dict["args"], path: path + "args", issues: &issues, usesJS: &usesJS)
        suggestions(dict["additionalSuggestions"], path: path + "additionalSuggestions", issues: &issues)
    }

    private static func args(_ node: Any?, path: String, issues: inout [String], usesJS: inout Bool) {
        guard let node else { return }
        let list = node as? [Any] ?? [node]
        for (i, arg) in list.enumerated() {
            let p = list.count > 1 ? "\(path)[\(i)]" : path
            guard let dict = check(arg, keys: argKeys, path: p, issues: &issues) else { continue }
            suggestions(dict["suggestions"], path: p + ".suggestions", issues: &issues)
            if let g = dict["generators"] {
                for gen in g as? [Any] ?? [g] {
                    if let gd = check(gen, keys: generatorKeys, path: p + ".generators", issues: &issues), gd["js"] != nil {
                        usesJS = true
                    }
                }
            }
        }
    }

    private static func suggestions(_ node: Any?, path: String, issues: inout [String]) {
        for item in node as? [Any] ?? [] where item is [String: Any] {
            _ = check(item, keys: suggestionKeys, path: path, issues: &issues)
        }
    }

    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a.lowercased()), b = Array(b.lowercased())
        var row = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var prev = row[0]
            row[0] = i
            for j in 1...max(b.count, 1) where !b.isEmpty {
                let tmp = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] == b[j - 1] ? 0 : 1))
                prev = tmp
            }
        }
        return row[b.count]
    }
}
