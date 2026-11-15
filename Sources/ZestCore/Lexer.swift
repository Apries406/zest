import Foundation

/// A word of the command line. Offsets count Unicode scalars, the same unit zsh uses
/// for `$CURSOR`.
public struct Token: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case word, separator, redirect }

    /// The word with quotes and backslashes removed.
    public var value: String
    public var start: Int
    public var end: Int
    public var kind: Kind
    /// The quote that is still open at the end of the word, if any.
    public var openQuote: Character?

    public init(value: String, start: Int, end: Int, kind: Kind = .word, openQuote: Character? = nil) {
        self.value = value
        self.start = start
        self.end = end
        self.kind = kind
        self.openQuote = openQuote
    }
}

/// The command the cursor is in, split into words.
public struct CommandContext: Equatable, Sendable {
    /// Finished words before the cursor, without redirections.
    public var words: [Token]
    /// The word being typed. Empty when the cursor follows a space.
    public var current: Token
    /// The current word follows `>`, `<` and similar, so it is a file name.
    public var currentIsRedirectTarget: Bool
    /// Where the command starts in the buffer.
    public var commandStart: Int
}

public enum Lexer {
    /// Splits `scalars` into tokens. Never fails: unfinished quotes end at the end of input.
    public static func tokenize(_ scalars: [Unicode.Scalar]) -> [Token] {
        var tokens: [Token] = []
        var i = 0
        let n = scalars.count

        func isSpace(_ c: Unicode.Scalar) -> Bool { c == " " || c == "\t" }
        func isOperatorChar(_ c: Unicode.Scalar) -> Bool {
            c == ";" || c == "&" || c == "|" || c == "(" || c == ")" || c == "`" || c == "\n" || c == "<" || c == ">"
        }

        while i < n {
            let c = scalars[i]
            if isSpace(c) { i += 1; continue }

            // Operators.
            if c == "\n" || c == ";" || c == "(" || c == ")" || c == "`" {
                var j = i + 1
                if c == ";", j < n, scalars[j] == ";" { j += 1 }
                tokens.append(Token(value: String(String.UnicodeScalarView(scalars[i..<j])), start: i, end: j, kind: .separator))
                i = j
                continue
            }
            if c == "|" || c == "&" {
                var j = i + 1
                if j < n, scalars[j] == c || (c == "|" && scalars[j] == "&") { j += 1 }
                if c == "&", j < n, scalars[j] == ">" {
                    // `&>` and `&>>` redirect output.
                    j += 1
                    if j < n, scalars[j] == ">" { j += 1 }
                    tokens.append(Token(value: String(String.UnicodeScalarView(scalars[i..<j])), start: i, end: j, kind: .redirect))
                    i = j
                    continue
                }
                tokens.append(Token(value: String(String.UnicodeScalarView(scalars[i..<j])), start: i, end: j, kind: .separator))
                i = j
                continue
            }
            if c == "<" || c == ">" {
                var j = i + 1
                while j < n, scalars[j] == "<" || scalars[j] == ">" || scalars[j] == "&" || scalars[j] == "|" { j += 1 }
                tokens.append(Token(value: String(String.UnicodeScalarView(scalars[i..<j])), start: i, end: j, kind: .redirect))
                i = j
                continue
            }
            if c == "$", i + 1 < n, scalars[i + 1] == "(" {
                tokens.append(Token(value: "$(", start: i, end: i + 2, kind: .separator))
                i += 2
                continue
            }

            // A word.
            let start = i
            var value = String.UnicodeScalarView()
            var quote: Unicode.Scalar? = nil
            while i < n {
                let ch = scalars[i]
                if let q = quote {
                    if ch == q {
                        quote = nil
                        i += 1
                    } else if q == "\"", ch == "\\", i + 1 < n, "\"\\$`".unicodeScalars.contains(scalars[i + 1]) {
                        value.append(scalars[i + 1])
                        i += 2
                    } else {
                        value.append(ch)
                        i += 1
                    }
                    continue
                }
                if isSpace(ch) || isOperatorChar(ch) { break }
                if ch == "$", i + 1 < n, scalars[i + 1] == "(" { break }
                if ch == "'" || ch == "\"" {
                    quote = ch
                    i += 1
                } else if ch == "\\" {
                    if i + 1 < n {
                        if scalars[i + 1] != "\n" { value.append(scalars[i + 1]) }
                        i += 2
                    } else {
                        i += 1
                    }
                } else {
                    value.append(ch)
                    i += 1
                }
            }
            // `2>file`: a word of digits right before `>` belongs to the redirection.
            if i < n, scalars[i] == ">" || scalars[i] == "<", !value.isEmpty, value.allSatisfy({ $0.properties.numericType != nil }) {
                var j = i + 1
                while j < n, scalars[j] == "<" || scalars[j] == ">" || scalars[j] == "&" { j += 1 }
                tokens.append(Token(value: String(String.UnicodeScalarView(scalars[start..<j])), start: start, end: j, kind: .redirect))
                i = j
                continue
            }
            tokens.append(Token(
                value: String(value), start: start, end: i, kind: .word,
                openQuote: quote.map { Character($0) }))
        }
        return tokens
    }

    /// Finds the command around `cursor` and the word being typed.
    public static func context(buffer: String, cursor: Int) -> CommandContext {
        let all = Array(buffer.unicodeScalars)
        let cursor = max(0, min(cursor, all.count))
        let before = Array(all[0..<cursor])
        let tokens = tokenize(before)

        var words: [Token] = []
        var redirectTargetPending = false
        var commandStart = 0
        var current = Token(value: "", start: cursor, end: cursor)
        var currentIsRedirectTarget = false

        // The last word is being typed unless whitespace or an operator follows it.
        let endsInWord: Bool = {
            guard let last = tokens.last, last.kind == .word else { return false }
            return last.end == cursor
        }()

        for (index, token) in tokens.enumerated() {
            let isCurrent = endsInWord && index == tokens.count - 1
            switch token.kind {
            case .separator:
                words.removeAll()
                redirectTargetPending = false
                commandStart = token.end
            case .redirect:
                redirectTargetPending = true
            case .word:
                if isCurrent {
                    current = token
                    currentIsRedirectTarget = redirectTargetPending
                } else if redirectTargetPending {
                    redirectTargetPending = false
                } else {
                    words.append(token)
                }
            }
        }
        if !endsInWord { currentIsRedirectTarget = redirectTargetPending }

        // Replace the whole word, including the part after the cursor.
        if current.openQuote == nil {
            var end = cursor
            while end < all.count {
                let ch = all[end]
                if ch == " " || ch == "\t" || ch == "\n" || ch == ";" || ch == "|" || ch == "&" || ch == ")" { break }
                end += 1
            }
            current.end = end
        }
        return CommandContext(
            words: words, current: current,
            currentIsRedirectTarget: currentIsRedirectTarget, commandStart: commandStart)
    }
}

extension String {
    /// Escapes characters that the shell would otherwise interpret.
    public func shellEscaped(inQuote quote: Character? = nil) -> String {
        switch quote {
        case "'":
            return replacingOccurrences(of: "'", with: "'\\''")
        case "\"":
            var out = ""
            for ch in self {
                if "\"\\$`".contains(ch) { out.append("\\") }
                out.append(ch)
            }
            return out
        default:
            var out = ""
            for ch in self {
                if " \t'\"\\$`!&|;()<>*?[]{}#~".contains(ch) { out.append("\\") }
                out.append(ch)
            }
            return out
        }
    }

    var scalarCount: Int { unicodeScalars.count }
}
