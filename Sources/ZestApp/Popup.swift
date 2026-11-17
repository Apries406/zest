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

    /// Called when the popup closed by itself: the terminal window closed or changed, or
    /// it changed size in a terminal whose cursor position comes from the shell. The
    /// popup stays closed until the next key, when the shell reports where it is.
    var onDismiss: (() -> Void)?

    // Follow the terminal window while the popup is open.
    private var followTimer: Timer?
    private var interactionMonitor: Any?
    private var missedTicks = 0
    private var shown: (state: CompletionController.State, width: CGFloat, window: CaretLocator.Window)?

    func hide() {
        stopFollowing()
        if panel.isVisible {
            panel.orderOut(nil)
            Log.popup.debug("closed")
        }
    }

    private func stopFollowing() {
        if let interactionMonitor { NSEvent.removeMonitor(interactionMonitor) }
        interactionMonitor = nil
        missedTicks = 0
        followTimer?.invalidate()
        followTimer = nil
        shown = nil
    }

    private func startFollowing(_ state: CompletionController.State, width: CGFloat, front: NSRunningApplication,
                                windowAnchored: Bool = false) {
        guard let window = CaretLocator.focusedWindow(of: front) else {
            stopFollowing()
            return
        }
        shown = (state, width, window)
        if !windowAnchored, let interactionMonitor {
            NSEvent.removeMonitor(interactionMonitor)
            self.interactionMonitor = nil
        }
        if windowAnchored, interactionMonitor == nil {
            // 无法判断编辑器内的焦点变化；点击或使用快捷键时关闭，避免列表遮挡代码。
            interactionMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
                if event.type == .keyDown, event.modifierFlags.intersection([.command, .control]).isEmpty { return }
                self?.hide()
                self?.onDismiss?()
            }
        }
        guard followTimer == nil else { return }
        followTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }
    }

    /// Moves the popup with the terminal window (dragging, resizing), and closes it when
    /// that window closes or another window comes to the front.
    private func follow() {
        guard let shown, panel.isVisible else { return }
        let window = NSWorkspace.shared.frontmostApplication.flatMap(CaretLocator.focusedWindow(of:))
        // Electron apps sometimes miss an Accessibility request; give a closed window a
        // few ticks before closing the popup.
        guard let window,
              CFEqual(window.element, shown.window.element) || window.frame == shown.window.frame
        else {
            missedTicks += 1
            if missedTicks >= 3 {
                Log.popup.debug("hidden: the terminal window closed or another one is in front")
                hide()
                onDismiss?()
            }
            return
        }
        missedTicks = 0
        guard window.frame != shown.window.frame else { return }
        if shown.state.start != nil, window.frame.size != shown.window.frame.size {
            Log.popup.debug("hidden: terminal window resized; waiting for the shell to report the cursor again")
            hide()
            onDismiss?()
            return
        }
        show(shown.state, width: shown.width)
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
        let caret = CaretLocator.caret(for: front, start: state.start, cursor: state.line?.cursor)
        // shortcut: Zed / Wu 未暴露终端光标时使用窗口锚点；提供光标接口后可移除。
        let window = caret == nil && Self.isZedEditor(bundle) ? CaretLocator.focusedWindow(of: front) : nil
        guard caret != nil || window != nil else {
            Log.popup.debug("hidden: no text cursor found in \(bundle, privacy: .public)")
            hide()
            return
        }
        if model.items != state.items { model.items = state.items }
        if model.selected != state.selected { model.selected = state.selected }
        if model.isLoading != state.isLoading { model.isLoading = state.isLoading }

        let height = model.height(itemCount: state.items.count)
        if let window, caret == nil {
            let bounds = CaretLocator.toCocoa(window.frame)
            let screen = NSScreen.screens.max { lhs, rhs in
                let a = lhs.visibleFrame.intersection(bounds)
                let b = rhs.visibleFrame.intersection(bounds)
                return a.width * a.height < b.width * b.height
            }
            guard let screen, let frame = Self.windowPopupFrame(bundle: bundle, window: bounds,
                screen: screen.visibleFrame, size: CGSize(width: width, height: height)) else {
                hide()
                return
            }
            Log.popup.debug("window-anchored popup in \(bundle, privacy: .public) at \(frame.debugDescription, privacy: .public)")
            panel.setFrame(frame, display: true)
            if !panel.isVisible { panel.orderFrontRegardless() }
            startFollowing(state, width: width, front: front, windowAnchored: true)
            return
        }
        guard let caret else { return }
        Log.popup.debug("shown in \(bundle, privacy: .public) at \(caret.rect.debugDescription, privacy: .public)")
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
        startFollowing(state, width: width, front: front)
    }

    /// The popup is only shown while the terminal that sent the line is in front.
    static func belongs(session app: String, to front: NSRunningApplication) -> Bool {
        belongs(session: app, bundle: front.bundleIdentifier)
    }

    static func belongs(session app: String, bundle: String?) -> Bool {
        guard !app.isEmpty, let bundle else { return true }
        if app == bundle { return true }
        // $TERM_PROGRAM values, when the shell did not inherit __CFBundleIdentifier.
        switch app {
        case "Apple_Terminal": return bundle == "com.apple.Terminal"
        case "iTerm.app": return bundle == "com.googlecode.iterm2"
        case "zed": return isZedEditor(bundle)
        case "vscode": return bundle == "com.microsoft.VSCode" || bundle.hasPrefix("com.todesktop.")
            || bundle == "com.vscodium" || bundle == "com.microsoft.VSCodeInsiders"
        default: return false
        }
    }

    private static func isZedEditor(_ bundle: String) -> Bool {
        ["dev.zed.Zed", "dev.zed.Zed-Preview", "dev.zed.Zed-Nightly", "dev.zed.Zed-Dev", "me.farshed.Wu"].contains(bundle)
    }

    /// 窗口与屏幕均使用 Cocoa 坐标；为状态栏留出空间，且不推测终端面板的位置。
    static func windowPopupFrame(bundle: String, window: CGRect, screen: CGRect, size: CGSize) -> CGRect? {
        guard isZedEditor(bundle) else { return nil }
        let visible = window.intersection(screen)
        let width = min(size.width, visible.width - 24)
        let height = min(size.height, visible.height - 56)
        guard !visible.isNull, width > 0, height > 0 else { return nil }
        return CGRect(x: visible.maxX - 12 - width, y: visible.minY + 44, width: width, height: height)
    }
}

