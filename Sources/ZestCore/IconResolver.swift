import Foundation

/// Picks the icon for a suggestion.
///
/// Files and folders use Material Icon Theme, like VS Code with that theme. Commands
/// use the Material icon of the tool when there is one (git, docker, node, ...).
/// Subcommands, options and arguments use Codicons, VS Code's own symbol icons.
public struct IconResolver: Sendable {
    public enum Icon: Equatable, Sendable {
        /// An SVG in assets/icons/material.
        case material(String)
        /// A Codicons glyph name; `role` picks the color.
        case codicon(String, role: Role)
        /// An emoji from the spec, e.g. `📦`.
        case emoji(String)
    }

    public enum Role: String, Sendable {
        case command, subcommand, option, argument, history
    }

    struct Index: Decodable {
        var file: String
        var folder: String
        var fileExtensions: [String: String]
        var fileNames: [String: String]
        var folderNames: [String: String]
    }

    private let index: Index?
    private let available: Set<String>

    /// Commands whose Material icon has a different name.
    static let commandIcons: [String: String] = [
        "node": "nodejs", "npx": "npm", "pip": "python", "pip3": "python", "python3": "python",
        "pipx": "python", "uv": "python", "poetry": "python", "kubectl": "kubernetes", "k9s": "kubernetes",
        "minikube": "kubernetes", "cargo": "rust", "rustc": "rust", "rustup": "rust",
        "docker-compose": "docker", "gh": "github", "code": "vscode", "cursor": "cursor",
        "mvn": "maven", "gem": "ruby", "bundle": "ruby", "rails": "rails", "composer": "composer",
        "gcloud": "gcp", "az": "azure", "tsc": "typescript", "ts-node": "typescript",
        "vue": "vue", "ng": "angular", "nest": "nest", "next": "next", "nuxt": "nuxt",
        "go": "go", "gofmt": "go", "swift": "swift", "xcodebuild": "swift", "brew": "terminal",
        "psql": "database", "mysql": "database", "sqlite3": "database", "redis-cli": "redis",
        "claude": "claude", "ffmpeg": "video", "ffprobe": "video", "make": "makefile",
        "cmake": "cmake", "java": "java", "javac": "java", "kotlin": "kotlin", "dotnet": "csharp",
        "php": "php", "deno": "deno", "bun": "bun", "yarn": "yarn", "pnpm": "pnpm", "npm": "npm",
    ]

    public init(indexURL: URL?, iconsDirectory: URL?) {
        if let indexURL, let data = try? Data(contentsOf: indexURL) {
            index = try? JSONDecoder().decode(Index.self, from: data)
        } else {
            index = nil
        }
        var names = Set<String>()
        if let dir = iconsDirectory, let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for file in files where file.hasSuffix(".svg") { names.insert(String(file.dropLast(4))) }
        }
        available = names
    }

    public func icon(for item: Completion) -> Icon {
        if let custom = item.icon, let icon = specIcon(custom) { return icon }
        switch item.kind {
        case .file: return .material(fileIcon(item.name))
        case .folder: return .material(folderIcon(item.name))
        case .command:
            let name = Self.commandIcons[item.name] ?? item.name
            return available.contains(name) ? .material(name) : .codicon("terminal", role: .command)
        case .subcommand: return .codicon("symbol-method", role: .subcommand)
        case .option: return .codicon("symbol-property", role: .option)
        case .argument: return .codicon("symbol-variable", role: .argument)
        case .history: return .codicon("history", role: .history)
        }
    }

    /// Icons written in specs: an emoji, `fig://icon?type=git`, or a Material icon name.
    private func specIcon(_ value: String) -> Icon? {
        if value.hasPrefix("type:") {
            switch value.dropFirst(5) {
            case "folder": return .material(index?.folder ?? "folder")
            case "file": return .material(index?.file ?? "file")
            default: return nil
            }
        }
        if value.hasPrefix("fig://icon?type=") {
            let type = String(value.dropFirst("fig://icon?type=".count)).split(separator: "&").first.map(String.init) ?? ""
            let name = Self.commandIcons[type] ?? type
            return available.contains(name) ? .material(name) : nil
        }
        if value.hasPrefix("fig://") || value.hasPrefix("http") { return nil }
        if available.contains(value) { return .material(value) }
        if value.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) { return .emoji(value) }
        return nil
    }

    public func fileIcon(_ name: String) -> String {
        guard let index else { return "file" }
        let lower = name.lowercased()
        if let icon = index.fileNames[lower] { return icon }
        // Longest extension first: `d.ts` before `ts`.
        var rest = Substring(lower)
        while let dot = rest.firstIndex(of: ".") {
            rest = rest[rest.index(after: dot)...]
            if let icon = index.fileExtensions[String(rest)] { return icon }
        }
        return index.file
    }

    public func folderIcon(_ name: String) -> String {
        guard let index else { return "folder" }
        let bare = name.hasSuffix("/") ? String(name.dropLast()) : name
        return index.folderNames[bare.lowercased()] ?? index.folder
    }
}
