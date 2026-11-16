import AppKit
import ApplicationServices
import OSLog

/// Debug messages; watch them with
/// `log stream --level debug --predicate 'subsystem == "io.github.rostik32.zest"'`.
enum Log {
    static let popup = Logger(subsystem: "io.github.rostik32.zest", category: "popup")
}

/// Finds where the text cursor is on screen, using the Accessibility API.
///
/// - Terminal.app and iTerm2 expose the terminal as a text area; we ask for the bounds of
///   the insertion point.
/// - Ghostty's text area has no bounds for text ranges, so the popup can't be placed there.
/// - VS Code and Cursor (Electron, xterm.js) only build their accessibility tree when
///   asked to via `AXManualAccessibility`. The focused element is then xterm's hidden
///   text area, which xterm keeps on top of the cursor for input methods.
enum CaretLocator {
    /// The cursor rectangle in Cocoa screen coordinates (origin bottom-left), plus the
    /// width of one character when known.
    struct Caret {
        var rect: CGRect
        var cellWidth: CGFloat?
    }

    private static var manualAccessibilityEnabled = Set<pid_t>()

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func caret(for app: NSRunningApplication) -> Caret? {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.2)

        if isElectron(app), !manualAccessibilityEnabled.contains(pid) {
            AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            manualAccessibilityEnabled.insert(pid)
        }

        guard let focused: AXUIElement = attribute(appElement, kAXFocusedUIElementAttribute) else {
            Log.popup.debug("no focused accessibility element")
            return nil
        }
        let role: String = attribute(focused, kAXRoleAttribute) ?? "?"
        Log.popup.debug("focused element: \(role, privacy: .public), insertion point: \(insertionPointBounds(focused).map { $0.debugDescription } ?? "none", privacy: .public), frame: \(frame(of: focused).map { $0.debugDescription } ?? "none", privacy: .public)")

        if let rect = insertionPointBounds(focused), isUsable(rect) {
            return Caret(rect: toCocoa(rect), cellWidth: rect.width > 2 && rect.width < 40 ? rect.width : nil)
        }
        if let frame = frame(of: focused), isUsable(frame), frame.height < 80 {
            return Caret(rect: toCocoa(frame), cellWidth: frame.width > 2 && frame.width < 40 ? frame.width : nil)
        }
        return nil
    }

    static func forget(pid: pid_t) {
        manualAccessibilityEnabled.remove(pid)
    }

    // MARK: - Accessibility helpers

    private static func isElectron(_ app: NSRunningApplication) -> Bool {
        guard let url = app.bundleURL else { return false }
        let framework = url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        return FileManager.default.fileExists(atPath: framework.path)
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else { return nil }
        return value as? T
    }

    private static func insertionPointBounds(_ element: AXUIElement) -> CGRect? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &range) else { return nil }

        // Some apps return an empty rectangle for a zero-length range; try one character.
        // iTerm2 returns a zero-width caret; the one-character rectangle gives the cell width.
        guard var rect = bounds(element, location: range.location, length: 0)
                ?? bounds(element, location: range.location, length: 1)
        else { return nil }
        if rect.width < 1, let cell = bounds(element, location: range.location, length: 1),
           abs(cell.minY - rect.minY) < 1 {
            rect.size.width = cell.width
        }
        return rect
    }

    private static func bounds(_ element: AXUIElement, location: Int, length: Int) -> CGRect? {
        var probe = CFRange(location: location, length: length)
        guard let probeValue = AXValueCreate(.cfRange, &probe) else { return nil }
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, probeValue, &boundsRef) == .success,
            let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect), rect.height > 0 else { return nil }
        return rect
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionRef: AXValue = attribute(element, kAXPositionAttribute),
              let sizeRef: AXValue = attribute(element, kAXSizeAttribute)
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRef, .cgPoint, &point), AXValueGetValue(sizeRef, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    private static func isUsable(_ rect: CGRect) -> Bool {
        rect.height > 0 && rect.height < 200 && NSScreen.screens.contains { screen in
            toCocoa(rect).intersects(screen.frame.insetBy(dx: -2, dy: -2))
        }
    }

    /// Accessibility uses a top-left origin on the main screen; Cocoa uses bottom-left.
    static func toCocoa(_ rect: CGRect) -> CGRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }
}
