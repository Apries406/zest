import AppKit
import SwiftUI
import ZestCore

/// What the popup view shows.
@MainActor
final class PopupModel: ObservableObject {
    @Published var items: [Completion] = []
    @Published var selected = 0
    @Published var isLoading = false
    @Published var fontSize: CGFloat = 13
    @Published var visibleRows = 8
    @Published var showDescriptions = true

    var rowHeight: CGFloat { (fontSize + 9).rounded() }
    var footerHeight: CGFloat { showDescriptions ? rowHeight + 2 : 0 }
    var iconSize: CGFloat { (fontSize + 3).rounded() }

    func height(itemCount: Int) -> CGFloat {
        CGFloat(min(itemCount, visibleRows)) * rowHeight + footerHeight + 8
    }
}

/// A borderless panel that floats above the terminal without taking focus, so every
/// key still goes to the shell.
final class PopupPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        level = .popUpMenu
        isFloatingPanel = true
        hidesOnDeactivate = false
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shows, moves and hides the popup.
@MainActor
final class PopupController {
    let model = PopupModel()
    private let panel = PopupPanel()
    private let icons: IconResolver

    init(icons: IconResolver) {
        self.icons = icons
        let host = NSHostingView(rootView: PopupView(model: model, icons: icons))
        host.translatesAutoresizingMaskIntoConstraints = true
        panel.contentView = host
    }

    func hide() {
        if panel.isVisible { panel.orderOut(nil) }
    }

    func show(_ state: CompletionController.State, width: CGFloat) {
        guard state.visible, !state.items.isEmpty,
              let front = NSWorkspace.shared.frontmostApplication,
              Self.belongs(session: state.app, to: front),
              let caret = CaretLocator.caret(for: front)
        else {
            hide()
            return
        }

        if model.items != state.items { model.items = state.items }
        if model.selected != state.selected { model.selected = state.selected }
        if model.isLoading != state.isLoading { model.isLoading = state.isLoading }

        let height = model.height(itemCount: state.items.count)
        // Line up the suggestion text with the start of the word being completed.
        var x = caret.rect.minX
        if let cell = caret.cellWidth, let line = state.line, let first = state.items.first {
            let typed = max(0, line.cursor - first.replaceStart)
            x -= CGFloat(typed) * cell
        }
        x -= model.iconSize + 14

        let screen = NSScreen.screens.first { $0.frame.contains(caret.rect.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var y = caret.rect.minY - 4 - height
        if y < visible.minY { y = caret.rect.maxY + 4 }  // Not enough room below: open upwards.
        x = min(max(x, visible.minX + 4), visible.maxX - width - 4)

        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// The popup is only shown while the terminal that sent the line is in front.
    static func belongs(session app: String, to front: NSRunningApplication) -> Bool {
        guard !app.isEmpty, let bundle = front.bundleIdentifier else { return true }
        if app == bundle { return true }
        // $TERM_PROGRAM values, when the shell did not inherit __CFBundleIdentifier.
        switch app {
        case "Apple_Terminal": return bundle == "com.apple.Terminal"
        case "vscode": return bundle == "com.microsoft.VSCode" || bundle.hasPrefix("com.todesktop.")
            || bundle == "com.vscodium" || bundle == "com.microsoft.VSCodeInsiders"
        default: return false
        }
    }
}

// MARK: - View

struct PopupView: View {
    @ObservedObject var model: PopupModel
    let icons: IconResolver

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.items.enumerated()), id: \.offset) { index, item in
                            Row(item: item, selected: index == model.selected, model: model, icons: icons)
                                .id(index)
                        }
                    }
                }
                .onChange(of: model.selected) { _, new in proxy.scrollTo(new) }
                .onChange(of: model.items) { _, _ in proxy.scrollTo(model.selected) }
            }
            if model.showDescriptions {
                Rectangle().fill(Theme.border).frame(height: 1)
                Footer(model: model)
            }
        }
        .padding(.vertical, 4)
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

private struct Row: View {
    let item: Completion
    let selected: Bool
    @ObservedObject var model: PopupModel
    let icons: IconResolver

    var body: some View {
        HStack(spacing: 8) {
            IconView(icon: icons.icon(for: item), size: model.iconSize)
            Text(highlighted)
                .font(.custom("Menlo", size: model.fontSize))
                .lineLimit(1)
                .strikethrough(item.deprecated, color: Theme.dim)
            Spacer(minLength: 12)
            if model.showDescriptions, let description = item.description, !selected {
                Text(description)
                    .font(.system(size: model.fontSize - 2))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 180, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: model.rowHeight)
        .background(selected ? Theme.selection : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .padding(.horizontal, 4)
    }

    private var highlighted: AttributedString {
        var text = AttributedString(item.name)
        text.foregroundColor = selected ? Theme.selectedText : Theme.text
        let characters = Array(item.name)
        for index in item.matchedIndices where index < characters.count {
            let start = text.index(text.startIndex, offsetByCharacters: index)
            let end = text.index(start, offsetByCharacters: 1)
            text[start..<end].foregroundColor = Theme.match
            text[start..<end].font = .custom("Menlo-Bold", size: model.fontSize)
        }
        return text
    }
}

private struct Footer: View {
    @ObservedObject var model: PopupModel

    var body: some View {
        HStack(spacing: 6) {
            let item = model.items.indices.contains(model.selected) ? model.items[model.selected] : nil
            Text(item?.description ?? item?.name ?? "")
                .font(.system(size: model.fontSize - 1).italic())
                .foregroundStyle(Theme.subcommand)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if model.isLoading {
                ProgressView().controlSize(.mini).tint(Theme.dim)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: model.rowHeight)
    }
}

struct IconView: View {
    let icon: IconResolver.Icon
    let size: CGFloat

    var body: some View {
        Group {
            switch icon {
            case .material(let name):
                if let image = IconCache.shared.material(name) {
                    Image(nsImage: image).resizable().interpolation(.high)
                } else {
                    Codicon(name: "symbol-variable", color: Theme.dim, size: size)
                }
            case .codicon(let name, let role):
                Codicon(name: name, color: Self.color(role), size: size)
            case .emoji(let emoji):
                Text(emoji).font(.system(size: size - 3))
            }
        }
        .frame(width: size, height: size)
    }

    static func color(_ role: IconResolver.Role) -> Color {
        switch role {
        case .command: return Theme.command
        case .subcommand: return Theme.subcommand
        case .option: return Theme.option
        case .argument: return Theme.argument
        case .history: return Theme.history
        }
    }
}

private struct Codicon: View {
    let name: String
    let color: Color
    let size: CGFloat

    var body: some View {
        Text(IconCache.shared.codicon(name))
            .font(.custom("codicon", size: size - 1))
            .foregroundStyle(color)
    }
}

/// Loads icons on first use and keeps them.
@MainActor
final class IconCache {
    static let shared = IconCache()
    var materialDirectory: URL?
    private var images: [String: NSImage] = [:]
    private var codepoints: [String: String] = [:]

    func configure(icons: URL?) {
        guard let icons else { return }
        materialDirectory = icons.appendingPathComponent("material")
        let font = icons.appendingPathComponent("codicon.ttf")
        CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil)
        if let data = try? Data(contentsOf: icons.appendingPathComponent("codicons.json")),
           let map = try? JSONDecoder().decode([String: String].self, from: data) {
            for (name, hex) in map {
                if let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) {
                    codepoints[name] = String(Character(scalar))
                }
            }
        }
    }

    func material(_ name: String) -> NSImage? {
        if let image = images[name] { return image }
        guard let url = materialDirectory?.appendingPathComponent(name + ".svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        images[name] = image
        return image
    }

    func codicon(_ name: String) -> String {
        codepoints[name] ?? "•"
    }
}
