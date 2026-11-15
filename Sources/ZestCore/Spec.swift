import Foundation

// The completion spec format. One spec describes one command.
// Field names follow the Fig spec format (https://fig.io/docs/reference) so that
// existing knowledge and specs carry over. See docs/spec-format.md.

/// A spec is the root subcommand of a command, e.g. `git`.
public typealias Spec = Subcommand

public struct Subcommand: Codable, Sendable, Equatable {
    public var name: Names
    public var displayName: String?
    public var description: String?
    public var icon: String?
    public var priority: Double?
    public var hidden: Bool?
    public var deprecated: Bool?
    public var insertValue: String?
    public var subcommands: [Subcommand]?
    public var options: [Option]?
    public var args: OneOrMany<Arg>?
    /// Load this subcommand's definition from another spec file, e.g. `aws/s3`.
    public var loadSpec: String?
    public var requiresSubcommand: Bool?
    public var filterStrategy: FilterStrategy?
    public var parserDirectives: ParserDirectives?
    public var additionalSuggestions: [Suggestion]?

    public init(
        name: Names, description: String? = nil, subcommands: [Subcommand]? = nil,
        options: [Option]? = nil, args: OneOrMany<Arg>? = nil
    ) {
        self.name = name
        self.description = description
        self.subcommands = subcommands
        self.options = options
        self.args = args
    }
}

public struct Option: Codable, Sendable, Equatable {
    public var name: Names
    public var displayName: String?
    public var description: String?
    public var icon: String?
    public var priority: Double?
    public var hidden: Bool?
    public var deprecated: Bool?
    public var insertValue: String?
    public var args: OneOrMany<Arg>?
    /// `true` = may repeat any number of times; a number = at most that many times.
    public var isRepeatable: Repeatable?
    /// Also valid for every subcommand below the one that defines it.
    public var isPersistent: Bool?
    public var isRequired: Bool?
    /// `true` means `=`; a string is the separator itself, e.g. `:`.
    public var requiresSeparator: Separator?
    public var exclusiveOn: [String]?
    public var dependsOn: [String]?

    public init(name: Names, description: String? = nil, args: OneOrMany<Arg>? = nil) {
        self.name = name
        self.description = description
        self.args = args
    }
}

public struct Arg: Codable, Sendable, Equatable {
    public var name: String?
    public var description: String?
    public var isOptional: Bool?
    public var isVariadic: Bool?
    public var optionsCanBreakVariadicArg: Bool?
    /// The rest of the line is another command, e.g. `sudo <command>`.
    public var isCommand: Bool?
    public var isScript: Bool?
    public var template: OneOrMany<Template>?
    public var suggestions: [Suggestion]?
    public var generators: OneOrMany<Generator>?
    public var `default`: String?
    public var filterStrategy: FilterStrategy?
    public var loadSpec: String?
    public var suggestCurrentToken: Bool?

    public init(
        name: String? = nil, description: String? = nil, isOptional: Bool? = nil,
        isVariadic: Bool? = nil, template: OneOrMany<Template>? = nil,
        suggestions: [Suggestion]? = nil, generators: OneOrMany<Generator>? = nil
    ) {
        self.name = name
        self.description = description
        self.isOptional = isOptional
        self.isVariadic = isVariadic
        self.template = template
        self.suggestions = suggestions
        self.generators = generators
    }
}

public struct Suggestion: Codable, Sendable, Equatable {
    public var name: Names
    public var displayName: String?
    public var description: String?
    public var icon: String?
    public var priority: Double?
    public var insertValue: String?
    public var hidden: Bool?
    public var deprecated: Bool?
    /// Fig suggestion type, e.g. `file`, `folder`, `special`. Only used for icons.
    public var type: String?

    public init(name: Names, description: String? = nil, insertValue: String? = nil) {
        self.name = name
        self.description = description
        self.insertValue = insertValue
    }

    // A suggestion may be written as a plain string.
    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let string = try? single.decode(String.self) {
            self.init(name: Names(string))
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decode(Names.self, forKey: .name))
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        priority = try c.decodeIfPresent(Double.self, forKey: .priority)
        insertValue = try c.decodeIfPresent(String.self, forKey: .insertValue)
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden)
        deprecated = try c.decodeIfPresent(Bool.self, forKey: .deprecated)
        type = try c.decodeIfPresent(String.self, forKey: .type)
    }
}

/// Produces suggestions at runtime, e.g. git branches.
public struct Generator: Codable, Sendable, Equatable {
    /// A shell command (string, run with `zsh -c`) or an argv array.
    public var script: Script?
    /// Split the script output into suggestions on this string. Default: newline.
    public var splitOn: String?
    /// List files and/or folders instead of running a script.
    public var template: OneOrMany<Template>?
    /// Only show some of the files listed by `template`.
    public var filter: TemplateFilter?
    public var cache: GeneratorCache?
    /// Seconds before the script is killed. Default: 5.
    public var scriptTimeout: Double?
    /// Re-run the generator when this character is typed, e.g. `/` or `,`.
    public var trigger: String?
    /// Only the text after the last occurrence of this string is used as the query.
    public var getQueryTerm: String?
    /// References to JavaScript functions in the spec's companion `.js` file.
    /// Only produced by the Fig importer; new specs should not need this.
    public var js: JSRefs?

    public init(script: Script? = nil, splitOn: String? = nil, template: OneOrMany<Template>? = nil) {
        self.script = script
        self.splitOn = splitOn
        self.template = template
    }
}

/// Which files a `template` generator shows. A file is shown when any condition matches.
/// Folders are always shown, so you can navigate into them, unless `filterFolders` is set.
public struct TemplateFilter: Codable, Sendable, Equatable {
    /// File extensions without the dot, e.g. `[js, mjs, json]`. `tar.gz` works too.
    public var extensions: [String]?
    /// Exact file names, e.g. `[Makefile]`.
    public var equals: [String]?
    /// A regular expression the file name must match.
    public var matches: String?
    public var filterFolders: Bool?

    public init(extensions: [String]? = nil, equals: [String]? = nil, matches: String? = nil) {
        self.extensions = extensions
        self.equals = equals
        self.matches = matches
    }

    func accepts(_ name: String, isDirectory: Bool) -> Bool {
        if isDirectory && filterFolders != true { return true }
        let bare = isDirectory && name.hasSuffix("/") ? String(name.dropLast()) : name
        if let equals, equals.contains(bare) { return true }
        if let matches, bare.range(of: matches, options: .regularExpression) != nil { return true }
        if let extensions {
            let parts = bare.split(separator: ".", omittingEmptySubsequences: false).dropFirst()
            // `a.tar.gz` matches `gz` and `tar.gz`.
            for i in parts.indices where extensions.contains(parts[i...].joined(separator: ".")) {
                return true
            }
        }
        return false
    }
}

public struct GeneratorCache: Codable, Sendable, Equatable {
    /// Seconds a result stays valid.
    public var ttl: Double?
    /// Cache results separately for every working directory.
    public var cacheByDirectory: Bool?
}

/// Indexes into the list of functions of a spec's companion JavaScript module.
public struct JSRefs: Codable, Sendable, Equatable {
    public var script: Int?
    public var postProcess: Int?
    public var custom: Int?
    public var trigger: Int?
    public var getQueryTerm: Int?
    public var filterTemplateSuggestions: Int?
}

public struct ParserDirectives: Codable, Sendable, Equatable {
    /// Options such as `-name` (one dash, several letters) are not split into `-n -a -m -e`.
    public var flagsArePosixNoncompliant: Bool?
    public var optionsMustPrecedeArguments: Bool?
    public var optionArgSeparators: OneOrMany<String>?
}

public enum Template: String, Codable, Sendable, Equatable {
    case filepaths, folders, history, help
}

public enum FilterStrategy: String, Codable, Sendable, Equatable {
    case prefix, fuzzy, `default`
}

// MARK: - Flexible value types

/// One name or several aliases: `name: commit` or `name: [-m, --message]`.
public struct Names: Codable, Sendable, Equatable, ExpressibleByStringLiteral, ExpressibleByArrayLiteral {
    public var all: [String]

    public init(_ name: String) { all = [name] }
    public init(_ names: [String]) { all = names }
    public init(stringLiteral value: String) { all = [value] }
    public init(arrayLiteral elements: String...) { all = elements }

    public var first: String { all.first ?? "" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            all = [s]
        } else {
            all = try c.decode([String].self)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if all.count == 1 { try c.encode(all[0]) } else { try c.encode(all) }
    }
}

/// A single value or a list: `args: {name: file}` or `args: [{name: src}, {name: dst}]`.
public struct OneOrMany<T: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    public var values: [T]

    public init(_ values: [T]) { self.values = values }
    public init(_ value: T) { values = [value] }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let list = try? c.decode([T].self) {
            values = list
        } else {
            values = [try c.decode(T.self)]
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if values.count == 1 { try c.encode(values[0]) } else { try c.encode(values) }
    }
}

public enum Script: Codable, Sendable, Equatable {
    case shell(String)
    case argv([String])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self = .shell(s)
        } else {
            self = .argv(try c.decode([String].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .shell(let s): try c.encode(s)
        case .argv(let a): try c.encode(a)
        }
    }
}

public enum Repeatable: Codable, Sendable, Equatable {
    case unlimited
    case times(Int)
    case no

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) {
            self = b ? .unlimited : .no
        } else {
            self = .times(try c.decode(Int.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .unlimited: try c.encode(true)
        case .no: try c.encode(false)
        case .times(let n): try c.encode(n)
        }
    }

    func allows(count: Int) -> Bool {
        switch self {
        case .unlimited: return true
        case .no: return count < 1
        case .times(let n): return count < n
        }
    }
}

public struct Separator: Codable, Sendable, Equatable {
    public var value: String?

    public init(_ value: String?) { self.value = value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) {
            value = b ? "=" : nil
        } else {
            value = try c.decode(String.self)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if value == "=" { try c.encode(true) } else if let v = value { try c.encode(v) } else { try c.encode(false) }
    }
}

extension Subcommand {
    var argList: [Arg] { args?.values ?? [] }
}

extension Option {
    var argList: [Arg] { args?.values ?? [] }
    var separator: String? { requiresSeparator?.value }
}
