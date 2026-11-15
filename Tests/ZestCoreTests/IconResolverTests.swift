import Testing
@testable import ZestCore

@Suite struct IconResolverTests {
    let icons = IconResolver(indexURL: Fixtures.iconIndex, iconsDirectory: Fixtures.iconDirectory)

    func item(_ kind: CompletionKind, _ name: String, icon: String? = nil) -> Completion {
        Completion(
            kind: kind, name: name, insertText: name, description: nil, icon: icon, matchedIndices: [],
            score: 0, appendSpace: false, replaceStart: 0, replaceEnd: 0, deprecated: false, usageKey: "")
    }

    @Test func files() {
        #expect(icons.icon(for: item(.file, "main.swift")) == .material("swift"))
        #expect(icons.icon(for: item(.file, "package.json")) == .material("nodejs"))
        #expect(icons.icon(for: item(.file, "types.d.ts")) == .material("typescript-def"))
        #expect(icons.icon(for: item(.file, "unknown.zzz")) == .material("file"))
    }

    @Test func folders() {
        #expect(icons.icon(for: item(.folder, "src/")) == .material("folder-src"))
        #expect(icons.icon(for: item(.folder, "random/")) == .material("folder"))
    }

    @Test func commands() {
        #expect(icons.icon(for: item(.command, "git")) == .material("git"))
        #expect(icons.icon(for: item(.command, "node")) == .material("nodejs"))
        #expect(icons.icon(for: item(.command, "no-such-tool")) == .codicon("terminal", role: .command))
    }

    @Test func kinds() {
        #expect(icons.icon(for: item(.subcommand, "commit")) == .codicon("symbol-method", role: .subcommand))
        #expect(icons.icon(for: item(.option, "--all")) == .codicon("symbol-property", role: .option))
    }

    @Test func specIcons() {
        #expect(icons.icon(for: item(.argument, "x", icon: "📦")) == .emoji("📦"))
        #expect(icons.icon(for: item(.argument, "x", icon: "fig://icon?type=git")) == .material("git"))
        #expect(icons.icon(for: item(.argument, "x", icon: "type:folder")) == .material("folder"))
    }
}
