import Foundation

/// Messages between shell/zest.zsh and the app. One message per line; fields are
/// separated by U+001F; newlines inside the command line travel as U+001E.
public enum ShellProtocol {
    public static let fieldSeparator: Character = "\u{1f}"
    public static let newline: Character = "\u{1e}"

    public struct Line: Equatable, Sendable {
        public var session: String
        public var cwd: String
        public var cursor: Int
        public var buffer: String

        public init(session: String, cwd: String, cursor: Int, buffer: String) {
            self.session = session
            self.cwd = cwd
            self.cursor = cursor
            self.buffer = buffer
        }
    }

    /// Where the terminal's cursor was (1-based row and column, from CSI 6n) while it
    /// stood at buffer index `cursor`, and the grid size. Sent for terminals that don't
    /// report their text cursor to macOS Accessibility.
    public struct GridPosition: Equatable, Sendable {
        public var row: Int
        public var column: Int
        public var rows: Int
        public var columns: Int
        public var cursor: Int

        public init(row: Int, column: Int, rows: Int, columns: Int, cursor: Int = 0) {
            self.row = row
            self.column = column
            self.rows = rows
            self.columns = columns
            self.cursor = cursor
        }

        /// The 0-based row and column of buffer index `index` (one cell per character).
        public func cell(at index: Int) -> (row: Int, column: Int) {
            let linear = max(0, (row - 1) * columns + (column - 1) + index - cursor)
            return (linear / columns, linear % columns)
        }
    }

    public enum Key: String, Sendable {
        case tab, up, down, enter, escape
    }

    public enum Message: Equatable, Sendable {
        /// A shell connected. `app` is the terminal's bundle id (or $TERM_PROGRAM).
        case hello(session: String, pid: Int32, app: String, historyFile: String)
        case aliases(session: String, [String: String])
        /// 由 zsh 在命令行下方显示候选项，不使用原生悬浮窗。
        case terminal(session: String)
        /// The command line changed.
        case line(Line)
        /// A key was pressed; the shell waits for a `Reply`.
        case key(sequence: String, key: Key, Line)
        /// The command line was accepted or cancelled.
        case end(session: String)
        /// A command is about to run (for history suggestions).
        case exec(session: String, command: String)
        /// Where the new command line starts on the terminal's grid.
        case position(session: String, GridPosition)
        /// The shell's connection closed (the shell exited, e.g. its window was closed).
        /// Not sent by the shell; the server reports it.
        case disconnected(session: String)
    }

    public enum Reply: Equatable, Sendable {
        /// The popup is closed: let the key do what it normally does.
        case pass
        /// The popup used the key (e.g. moved the selection).
        case consumed
        /// Replace the command line.
        case set(cursor: Int, buffer: String)
    }

    public static func parse(_ line: Substring) -> Message? {
        let f = line.split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init)
        guard let kind = f.first else { return nil }
        switch kind {
        case "hello" where f.count >= 5:
            return .hello(session: f[1], pid: Int32(f[2]) ?? 0, app: f[3], historyFile: f[4])
        case "aliases" where f.count >= 2:
            var map: [String: String] = [:]
            for item in f.dropFirst(2) {
                guard let eq = item.firstIndex(of: "=") else { continue }
                map[String(item[..<eq])] = String(item[item.index(after: eq)...])
            }
            return .aliases(session: f[1], map)
        case "terminal" where f.count == 2:
            return .terminal(session: f[1])
        case "line" where f.count >= 5:
            return lineState(Array(f[1...])).map(Message.line)
        case "key" where f.count >= 7:
            guard let key = Key(rawValue: f[2]), let state = lineState(Array(f[3...])) else { return nil }
            return .key(sequence: f[1], key: key, state)
        case "end" where f.count >= 2:
            return .end(session: f[1])
        case "pos" where f.count >= 6:
            guard let row = Int(f[2]), let column = Int(f[3]), let rows = Int(f[4]), let columns = Int(f[5]),
                  row > 0, column > 0, rows > 0, columns > 0 else { return nil }
            let cursor = f.count >= 7 ? Int(f[6]) ?? 0 : 0
            return .position(session: f[1], GridPosition(row: row, column: column, rows: rows, columns: columns, cursor: cursor))
        case "exec" where f.count >= 3:
            return .exec(session: f[1], command: decodeNewlines(f[2...].joined(separator: String(fieldSeparator))))
        default:
            return nil
        }
    }

    private static func lineState(_ f: [String]) -> Line? {
        guard f.count >= 4, let cursor = Int(f[2]) else { return nil }
        // The buffer is last and may itself contain the separator.
        let buffer = f[3...].joined(separator: String(fieldSeparator))
        return Line(session: f[0], cwd: f[1], cursor: cursor, buffer: decodeNewlines(buffer))
    }

    public static func format(_ reply: Reply, sequence: String) -> String {
        let s = String(fieldSeparator)
        switch reply {
        case .pass: return "r\(s)\(sequence)\(s)pass\n"
        case .consumed: return "r\(s)\(sequence)\(s)ok\n"
        case .set(let cursor, let buffer):
            return "r\(s)\(sequence)\(s)set\(s)\(cursor)\(s)\(encodeNewlines(buffer))\n"
        }
    }

    static func decodeNewlines(_ s: String) -> String {
        s.replacingOccurrences(of: String(newline), with: "\n")
    }

    static func encodeNewlines(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: String(newline))
    }
}
