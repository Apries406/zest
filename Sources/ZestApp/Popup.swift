import AppKit
import OSLog
import SwiftUI
import ZestCore
import ZestUI

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
        guard state.visible, !state.items.isEmpty, let front = NSWorkspace.shared.frontmostApplication else {
            hide()
            return
        }
        let bundle = front.bundleIdentifier ?? "?"
        guard Self.belongs(session: state.app, to: front) else {
            Log.popup.debug("hidden: shell from \(state.app, privacy: .public) is not in front (\(bundle, privacy: .public))")
            hide()
            return
        }
        guard let caret = CaretLocator.caret(for: front) else {
            Log.popup.debug("hidden: no text cursor found in \(bundle, privacy: .public)")
            hide()
            return
        }
        Log.popup.debug("shown in \(bundle, privacy: .public) at \(caret.rect.debugDescription, privacy: .public)")

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
        x -= model.iconSize + 20  // row padding (4 + 8) + icon + spacing (8)

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
        case "iTerm.app": return bundle == "com.googlecode.iterm2"
        case "vscode": return bundle == "com.microsoft.VSCode" || bundle.hasPrefix("com.todesktop.")
            || bundle == "com.vscodium" || bundle == "com.microsoft.VSCodeInsiders"
        default: return false
        }
    }
}

