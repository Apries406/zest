import Foundation
import ZestCore

/// Installs the zsh script and the line in ~/.zshrc that loads it.
enum ShellIntegration {
    static let begin = "# >>> zest >>>"
    static let end = "# <<< zest <<<"

    static var script: URL { Paths.appSupport.appendingPathComponent("zest.zsh") }
    static var settingsFile: URL { Paths.appSupport.appendingPathComponent("settings.zsh") }

    static var zshrc: URL {
        let dir = ProcessInfo.processInfo.environment["ZDOTDIR"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: dir).appendingPathComponent(".zshrc")
    }

    static var block: String {
        """
        \(begin)
        # Autocomplete popup for zsh. Keep this at the end of the file. https://github.com/rostik32/zest
        [[ -f "$HOME/Library/Application Support/zest/zest.zsh" ]] && source "$HOME/Library/Application Support/zest/zest.zsh"
        \(end)
        """
    }

    static var isInstalled: Bool {
        ((try? String(contentsOf: zshrc, encoding: .utf8)) ?? "").contains(begin)
    }

    /// Copies the zsh script from the app bundle. Runs at every launch so updates of the
    /// app also update the script.
    static func copyScript(from resources: URL?) {
        guard let source = resources.map({ $0.appendingPathComponent("zest.zsh") }) ?? Paths.zshScript,
              let data = try? Data(contentsOf: source) else { return }
        try? FileManager.default.createDirectory(at: Paths.appSupport, withIntermediateDirectories: true)
        if (try? Data(contentsOf: script)) != data {
            try? data.write(to: script, options: .atomic)
        }
    }

    /// Settings the shell reads when it starts.
    static func writeSettings(ghostText: Bool) {
        let text = """
        # Written by Zest.app; changes here are overwritten.
        ZEST_GHOST_TEXT=\(ghostText ? 1 : 0)

        """
        try? FileManager.default.createDirectory(at: Paths.appSupport, withIntermediateDirectories: true)
        try? text.write(to: settingsFile, atomically: true, encoding: .utf8)
    }

    /// Appends the block to ~/.zshrc. A backup is kept as ~/.zshrc.zest-backup.
    static func install() throws {
        var text = (try? String(contentsOf: zshrc, encoding: .utf8)) ?? ""
        guard !text.contains(begin) else { return }
        if FileManager.default.fileExists(atPath: zshrc.path) {
            let backup = zshrc.deletingLastPathComponent().appendingPathComponent(".zshrc.zest-backup")
            try? FileManager.default.removeItem(at: backup)
            try FileManager.default.copyItem(at: zshrc, to: backup)
        }
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += "\n" + block + "\n"
        try text.write(to: zshrc, atomically: true, encoding: .utf8)
    }

    static func uninstall() throws {
        guard let text = try? String(contentsOf: zshrc, encoding: .utf8),
              let start = text.range(of: begin), let stop = text.range(of: end, range: start.upperBound..<text.endIndex)
        else { return }
        var lower = start.lowerBound
        // Also remove the empty line we added before the block.
        if lower > text.startIndex, text[text.index(before: lower)] == "\n" {
            let before = text.index(before: lower)
            if before > text.startIndex, text[text.index(before: before)] == "\n" { lower = before }
        }
        var upper = stop.upperBound
        if upper < text.endIndex, text[upper] == "\n" { upper = text.index(after: upper) }
        var updated = text
        updated.removeSubrange(lower..<upper)
        try updated.write(to: zshrc, atomically: true, encoding: .utf8)
    }
}
