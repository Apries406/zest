import SwiftUI
import ZestCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: Updater

    var body: some View {
        TabView {
            GeneralTab(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            BehaviorTab()
                .tabItem { Label("Behavior", systemImage: "keyboard") }
            AppearanceTab(model: model)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            SpecsTab(model: model)
                .tabItem { Label("Specs", systemImage: "doc.text") }
            UpdatesTab(updater: updater)
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
        }
        .frame(width: 520)
        .padding(.vertical, 8)
    }
}

private struct StatusRow: View {
    let ok: Bool
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct GeneralTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Show suggestions", isOn: $model.enabled)
                Toggle("Start zest at login", isOn: Binding(
                    get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            }
            Section("Setup") {
                HStack {
                    StatusRow(
                        ok: model.accessibilityGranted, title: "Accessibility access",
                        detail: "Needed to place the popup under the cursor.")
                    Spacer()
                    if !model.accessibilityGranted {
                        Button("Open System Settings") { model.requestAccessibility() }
                    }
                }
                HStack {
                    StatusRow(
                        ok: model.shellInstalled, title: "zsh integration",
                        detail: "Three lines at the end of ~/.zshrc. Only zsh is supported.")
                    Spacer()
                    if model.shellInstalled {
                        Button("Remove") { model.uninstallShellIntegration() }
                    } else {
                        Button("Add to ~/.zshrc") { model.installShellIntegration() }
                    }
                }
                if let error = model.serverError {
                    StatusRow(ok: false, title: "zest could not start", detail: error)
                }
            }
            Section {
                Text("Open a new terminal window after changing the zsh integration.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct BehaviorTab: View {
    @AppStorage(Pref.enter) private var enter = CompletionController.EnterBehavior.smart.rawValue
    @AppStorage(Pref.fuzzy) private var fuzzy = true
    @AppStorage(Pref.history) private var history = true
    @AppStorage(Pref.ghostText) private var ghostText = true
    @AppStorage(Pref.pathCommands) private var pathCommands = true

    var body: some View {
        Form {
            Section("Keys") {
                Picker("Enter", selection: $enter) {
                    Text("Insert while typing a word, otherwise run").tag(CompletionController.EnterBehavior.smart.rawValue)
                    Text("Always insert the suggestion").tag(CompletionController.EnterBehavior.insert.rawValue)
                    Text("Always run the command").tag(CompletionController.EnterBehavior.run.rawValue)
                }
                LabeledContent("Tab", value: "Insert the suggestion")
                LabeledContent("↑ ↓", value: "Choose a suggestion")
                LabeledContent("Esc", value: "Close the popup")
                LabeledContent("→", value: "Accept the grey ghost text")
            }
            Section("Suggestions") {
                Toggle("Fuzzy matching (\"gco\" finds \"git-checkout\")", isOn: $fuzzy)
                Toggle("Suggest commands from history", isOn: $history)
                Toggle("Suggest every program on $PATH", isOn: $pathCommands)
                Toggle("Ghost text from history (new terminals)", isOn: $ghostText)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceTab: View {
    @ObservedObject var model: AppModel
    @AppStorage(Pref.fontSize) private var fontSize = 13.0
    @AppStorage(Pref.rows) private var rows = 8
    @AppStorage(Pref.width) private var width = 440.0
    @AppStorage(Pref.descriptions) private var descriptions = true

    var body: some View {
        Form {
            Section {
                LabeledContent("Theme", value: "One Dark Pro Darker")
                LabeledContent("Icons", value: "Material Icon Theme, Codicons")
                Stepper("Font size: \(Int(fontSize))", value: $fontSize, in: 10...20)
                Stepper("Visible rows: \(rows)", value: $rows, in: 3...20)
                Slider(value: $width, in: 300...800, step: 20) { Text("Width: \(Int(width))") }
                Toggle("Show descriptions", isOn: $descriptions)
            }
            Section("Preview") {
                PreviewPopup(model: model)
                    .frame(height: model.popup.model.height(itemCount: 4))
            }
        }
        .formStyle(.grouped)
    }
}

/// A static popup with sample items, so appearance changes are visible right away.
private struct PreviewPopup: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let icons = IconResolver(
            indexURL: model.resources?.appendingPathComponent("icons/material.json"),
            iconsDirectory: model.resources?.appendingPathComponent("icons/material"))
        PopupView(model: Self.sample(model.popup.model), icons: icons)
    }

    @MainActor
    static func sample(_ base: PopupModel) -> PopupModel {
        let preview = PopupModel()
        preview.fontSize = base.fontSize
        preview.visibleRows = 4
        preview.showDescriptions = base.showDescriptions
        func item(_ kind: CompletionKind, _ name: String, _ description: String?, _ matched: [Int]) -> Completion {
            Completion(kind: kind, name: name, insertText: name, description: description, icon: nil,
                       matchedIndices: matched, score: 0, appendSpace: true, replaceStart: 0, replaceEnd: 0,
                       deprecated: false, usageKey: "")
        }
        preview.items = [
            item(.subcommand, "checkout", "Switch branches or restore working tree files", [0, 1]),
            item(.subcommand, "cherry-pick", "Apply the changes introduced by some commits", [0, 1]),
            item(.folder, "src/", nil, []),
            item(.file, "Package.swift", nil, []),
        ]
        return preview
    }
}

private struct SpecsTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Built-in specs", value: "\(model.store.commands().count) commands")
                LabeledContent("Your specs", value: SpecStore.userSpecsDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                HStack {
                    Button("Open My Specs Folder") { model.openSpecsFolder() }
                    Button("Reload Specs") { model.reloadSpecs() }
                }
            }
            Section("Add a command") {
                Text("""
                Put a YAML file named after the command in your specs folder, e.g. mytool.yaml. \
                A spec in your folder replaces the built-in one with the same name.

                To start from the command's --help output, run:
                    zest gen mytool
                Then check it with:
                    zest validate
                """)
                .font(.callout)
                .textSelection(.enabled)
                Link("Spec format reference", destination: URL(string: "https://github.com/rostik32/zest/blob/main/docs/spec-format.md")!)
            }
        }
        .formStyle(.grouped)
    }
}

private struct UpdatesTab: View {
    @ObservedObject var updater: Updater
    @AppStorage(Pref.autoCheckUpdates) private var autoCheck = true
    @AppStorage(Pref.autoInstallUpdates) private var autoInstall = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: ZestVersion.current)
                Toggle("Check for updates automatically", isOn: $autoCheck)
                Toggle("Install updates without asking", isOn: $autoInstall)
                    .disabled(!autoCheck)
                HStack {
                    Button("Check Now") { Task { await updater.check(userInitiated: true) } }
                        .disabled(updater.status == .checking || updater.status == .installing)
                    Text(statusText).foregroundStyle(.secondary)
                }
            }
            Section {
                Text("Updates come from GitHub Releases of rostik32/zest. Each update is checked against its checksum and must be signed with the same certificate as this app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        switch updater.status {
        case .idle: return ""
        case .checking: return "Checking…"
        case .upToDate: return "Up to date"
        case .available(let v): return "Version \(v) is available"
        case .installing: return "Installing…"
        case .failed(let e): return "Failed: \(e)"
        }
    }
}
