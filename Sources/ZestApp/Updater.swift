import AppKit
import CryptoKit
import Foundation
import Security
import ZestCore

/// Checks GitHub Releases for a newer version and installs it.
///
/// A release has two assets: `Zest.zip` and `Zest.zip.sha256`. Before installing,
/// the updater checks the checksum and that the new app is signed with the same
/// certificate as the running one, so only releases from this project are accepted.
@MainActor
final class Updater: ObservableObject {
    static let repository = "rostik32/zest"

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case installing
        case failed(String)
    }

    struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }

        let tag_name: String
        let body: String?
        let html_url: URL
        let assets: [Asset]

        var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
    }

    @Published private(set) var status: Status = .idle
    private var latest: Release?
    private var timer: Timer?

    /// Checks once a day while automatic checks are on.
    func startSchedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
        checkIfDue()
    }

    private func checkIfDue() {
        let defaults = Pref.defaults
        guard defaults.bool(forKey: Pref.autoCheckUpdates) else { return }
        let last = defaults.double(forKey: Pref.lastUpdateCheck)
        guard Date().timeIntervalSince1970 - last > 86_400 else { return }
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        status = .checking
        Pref.defaults.set(Date().timeIntervalSince1970, forKey: Pref.lastUpdateCheck)
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("zest-updater", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 404 {
                status = .upToDate  // No releases yet.
                return
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            latest = release
            guard Self.isNewer(release.version, than: ZestVersion.current) else {
                status = .upToDate
                if userInitiated { alert("zest is up to date", "You have the latest version, \(ZestVersion.current).") }
                return
            }
            status = .available(version: release.version)
            if Pref.defaults.bool(forKey: Pref.autoInstallUpdates) && !userInitiated {
                await install()
            } else {
                offer(release)
            }
        } catch {
            status = .failed(error.localizedDescription)
            if userInitiated { alert("Could not check for updates", error.localizedDescription) }
        }
    }

    private func offer(_ release: Release) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "zest \(release.version) is available"
        alert.informativeText = "You have \(ZestVersion.current).\n\n" + String((release.body ?? "").prefix(600))
        alert.addButton(withTitle: "Install and Restart")
        alert.addButton(withTitle: "Release Notes")
        alert.addButton(withTitle: "Later")
        switch alert.runModal() {
        case .alertFirstButtonReturn: Task { await install() }
        case .alertSecondButtonReturn: NSWorkspace.shared.open(release.html_url)
        default: break
        }
    }

    func install() async {
        guard let release = latest,
              let zip = release.assets.first(where: { $0.name == "Zest.zip" }),
              let sum = release.assets.first(where: { $0.name == "Zest.zip.sha256" })
        else {
            status = .failed("the release has no Zest.zip")
            return
        }
        status = .installing
        do {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("zest-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let (zipFile, _) = try await URLSession.shared.download(from: zip.browser_download_url)
            let (sumData, _) = try await URLSession.shared.data(from: sum.browser_download_url)
            let expected = String(decoding: sumData, as: UTF8.self).split(separator: " ").first.map(String.init) ?? ""
            let actual = SHA256.hash(data: try Data(contentsOf: zipFile)).map { String(format: "%02x", $0) }.joined()
            guard !expected.isEmpty, expected.lowercased() == actual else {
                throw UpdateError("the download is damaged (checksum mismatch)")
            }
            try run("/usr/bin/ditto", ["-x", "-k", zipFile.path, work.path])
            let newApp = work.appendingPathComponent("Zest.app")
            try verifySignature(of: newApp)
            try relaunch(replacingWith: newApp)
        } catch {
            status = .failed(String(describing: error))
            alert("Could not install the update", String(describing: error))
        }
    }

    /// The new app must satisfy the running app's designated requirement, i.e. be
    /// signed with the same certificate.
    private func verifySignature(of app: URL) throws {
        var selfCode: SecCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode,
              let staticSelf = Self.staticCode(selfCode),
              SecCodeCopyDesignatedRequirement(staticSelf, [], &requirement) == errSecSuccess, let requirement
        else { throw UpdateError("cannot read this app's signature") }

        var newCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &newCode) == errSecSuccess, let newCode else {
            throw UpdateError("the new app is not signed")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidity(newCode, flags, requirement) == errSecSuccess else {
            throw UpdateError("the new app is not signed by the zest project")
        }
    }

    private static func staticCode(_ code: SecCode) -> SecStaticCode? {
        var result: SecStaticCode?
        return SecCodeCopyStaticCode(code, [], &result) == errSecSuccess ? result : nil
    }

    /// Replaces the running app after it quits, then opens the new one.
    private func relaunch(replacingWith newApp: URL) throws {
        let current = Bundle.main.bundleURL
        let script = """
        while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do /bin/sleep 0.2; done
        /bin/rm -rf "\(current.path)" && /bin/mv "\(newApp.path)" "\(current.path)" && /usr/bin/open "\(current.path)"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try process.run()
        NSApp.terminate(nil)
    }

    private func run(_ tool: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError("\(tool) failed") }
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    /// Compares dotted version numbers: 0.10.0 is newer than 0.9.3.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

struct UpdateError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
