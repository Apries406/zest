import Foundation
import ZestCore

/// User settings, stored in UserDefaults (`defaults read io.github.rostik32.zest`).
enum Pref {
    static let enabled = "enabled"
    static let enter = "enterBehavior"
    static let fuzzy = "fuzzy"
    static let history = "historySuggestions"
    static let ghostText = "ghostText"
    static let pathCommands = "pathCommands"
    static let rows = "visibleRows"
    static let fontSize = "fontSize"
    static let width = "popupWidth"
    static let descriptions = "showDescriptions"
    static let autoCheckUpdates = "autoCheckUpdates"
    static let autoInstallUpdates = "autoInstallUpdates"
    static let lastUpdateCheck = "lastUpdateCheck"
    static let onboarded = "onboarded"

    static func register() {
        UserDefaults.standard.register(defaults: [
            enabled: true,
            enter: CompletionController.EnterBehavior.smart.rawValue,
            fuzzy: true,
            history: true,
            ghostText: true,
            pathCommands: true,
            rows: 8,
            fontSize: 13.0,
            width: 440.0,
            descriptions: true,
            autoCheckUpdates: true,
            autoInstallUpdates: false,
        ])
    }

    static var defaults: UserDefaults { .standard }
}
