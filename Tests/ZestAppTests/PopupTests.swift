import AppKit
import Testing
@testable import ZestApp

@MainActor
@Suite struct PopupTests {
    @Test(arguments: ["dev.zed.Zed", "dev.zed.Zed-Preview", "dev.zed.Zed-Nightly", "dev.zed.Zed-Dev", "me.farshed.Wu"])
    func zedShellBelongsOnlyToZedEditors(bundle: String) {
        #expect(PopupController.belongs(session: "zed", bundle: bundle))
        #expect(PopupController.belongs(session: bundle, bundle: bundle))
        #expect(!PopupController.belongs(session: bundle, bundle: "com.apple.Terminal"))
    }

    @Test(arguments: ["com.apple.Terminal", "com.mitchellh.ghostty", "com.microsoft.VSCode", "dev.zed.Zed-Other", "me.farshed.Wu.other"])
    func unknownAppsDoNotGetZedFallback(bundle: String) {
        #expect(!PopupController.belongs(session: "zed", bundle: bundle))
        #expect(PopupController.windowPopupFrame(bundle: bundle,
            window: CGRect(x: 0, y: 0, width: 1000, height: 800),
            screen: CGRect(x: 0, y: 0, width: 1440, height: 900),
            size: CGSize(width: 440, height: 210)) == nil)
    }

    @Test func missingCaretUsesWindowCorner() throws {
        let frame = try #require(PopupController.windowPopupFrame(bundle: "me.farshed.Wu",
            window: CGRect(x: 100, y: 200, width: 1000, height: 700),
            screen: CGRect(x: 0, y: 0, width: 1440, height: 1000),
            size: CGSize(width: 440, height: 210)))
        #expect(frame == CGRect(x: 648, y: 244, width: 440, height: 210))
    }

    @Test func fallbackFitsSmallAndPartiallyOffscreenWindows() throws {
        let visible = CGRect(x: -1440, y: 30, width: 1440, height: 870)
        let window = CGRect(x: -1600, y: -100, width: 500, height: 400)
        let frame = try #require(PopupController.windowPopupFrame(bundle: "dev.zed.Zed",
            window: window, screen: visible, size: CGSize(width: 440, height: 400)))
        #expect(frame.width > 0 && frame.height > 0)
        #expect(window.contains(frame))
        #expect(visible.contains(frame))
    }

    @Test func noFallbackOutsideVisibleScreen() {
        #expect(PopupController.windowPopupFrame(bundle: "dev.zed.Zed",
            window: CGRect(x: 2000, y: 2000, width: 100, height: 100),
            screen: CGRect(x: 0, y: 0, width: 1440, height: 900),
            size: CGSize(width: 440, height: 210)) == nil)
    }
}
