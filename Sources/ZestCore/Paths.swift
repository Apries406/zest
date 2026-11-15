import Foundation

/// Where zest keeps its files.
public enum Paths {
    /// `~/Library/Application Support/zest`: socket, usage statistics, logs.
    public static var appSupport: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/zest", isDirectory: true)
    }

    /// The Unix socket zsh talks to. Must match `_zest_socket` in shell/zest.zsh.
    public static var socket: URL { appSupport.appendingPathComponent("zest.sock") }

    public static var usage: URL { appSupport.appendingPathComponent("usage.json") }

    /// The folder with built-in specs and the zsh script.
    ///
    /// In the app bundle that is `Contents/Resources`. When running from a checkout
    /// (`swift run zest`), it is the repository root. `ZEST_RESOURCES` overrides both.
    public static var resources: URL? {
        if let env = ProcessInfo.processInfo.environment["ZEST_RESOURCES"] {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        var dir = exe.deletingLastPathComponent()
        // Inside an app: <App>.app/Contents/MacOS/<exe> or <App>.app/Contents/Helpers/<exe>.
        let contents = dir.deletingLastPathComponent()
        if contents.lastPathComponent == "Contents" {
            return contents.appendingPathComponent("Resources", isDirectory: true)
        }
        if let main = Bundle.main.resourceURL, FileManager.default.fileExists(atPath: main.appendingPathComponent("specs").path) {
            return main
        }
        // A checkout: walk up to the folder that has Package.swift and specs/.
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path),
               FileManager.default.fileExists(atPath: dir.appendingPathComponent("specs").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    public static var builtInSpecs: URL? {
        guard let resources else { return nil }
        let url = resources.appendingPathComponent("specs", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public static var zshScript: URL? {
        guard let resources else { return nil }
        for candidate in ["zest.zsh", "shell/zest.zsh"] {
            let url = resources.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}
