import AppKit
import SwiftUI

/// Colors of the One Dark Pro Darker theme (zhuangtongfa.material-theme), taken from
/// its suggest widget so the popup looks like completions in Cursor / VS Code.
enum Theme {
    static let background = Color(hex: 0x1E2227)      // editorSuggestWidget.background
    static let selection = Color(hex: 0x2C313A)       // editorSuggestWidget.selectedBackground
    static let border = Color(hex: 0x181A1F)          // editorSuggestWidget.border
    static let text = Color(hex: 0xABB2BF)            // editor.foreground
    static let selectedText = Color(hex: 0xD7DAE0)    // list.activeSelectionForeground
    static let match = Color(hex: 0xECEBEB)           // list.highlightForeground
    static let dim = Color(hex: 0x7F848E)             // comments
    static let separator = Color(hex: 0x3E4452)       // focusBorder

    static let command = Color(hex: 0x8CC265)         // terminal.ansiGreen
    static let subcommand = Color(hex: 0xC162DE)      // terminal.ansiMagenta
    static let option = Color(hex: 0x4AA5F0)          // terminal.ansiBlue
    static let argument = Color(hex: 0xD18F52)        // terminal.ansiYellow
    static let history = dim
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}
