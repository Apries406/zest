import Foundation

/// File system access used by the engine. Replaced by a fake in tests.
public protocol FileSystem: Sendable {
    func list(_ path: String) -> [FileEntry]
    var homeDirectory: String { get }
}

public struct FileEntry: Equatable, Sendable {
    public var name: String
    public var isDirectory: Bool

    public init(name: String, isDirectory: Bool) {
        self.name = name
        self.isDirectory = isDirectory
    }
}

public struct LocalFileSystem: FileSystem {
    /// Directories with more entries than this are cut off to keep the popup fast.
    public var limit = 5000

    public init() {}

    public var homeDirectory: String { NSHomeDirectory() }

    public func list(_ path: String) -> [FileEntry] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }
        var result: [FileEntry] = []
        result.reserveCapacity(min(names.count, limit))
        for name in names.prefix(limit) {
            var isDir: ObjCBool = false
            let full = (path as NSString).appendingPathComponent(name)
            // fileExists follows symlinks, so a link to a folder counts as a folder.
            _ = FileManager.default.fileExists(atPath: full, isDirectory: &isDir)
            result.append(FileEntry(name: name, isDirectory: isDir.boolValue))
        }
        return result
    }
}

public struct ShellResult: Equatable, Sendable {
    public var stdout: String
    public var stderr: String
    public var status: Int32

    public init(stdout: String, stderr: String = "", status: Int32 = 0) {
        self.stdout = stdout
        self.stderr = stderr
        self.status = status
    }
}

/// Runs generator scripts. Replaced by a fake in tests.
public protocol ShellRunner: Sendable {
    func run(_ script: Script, cwd: String, timeout: TimeInterval) -> ShellResult
}

public struct ProcessShellRunner: ShellRunner {
    public init() {}

    public func run(_ script: Script, cwd: String, timeout: TimeInterval) -> ShellResult {
        let process = Process()
        switch script {
        case .shell(let command):
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            // -f: skip the user's startup files so scripts run fast and predictably.
            process.arguments = ["-f", "-c", command]
        case .argv(let argv):
            guard let first = argv.first else { return ShellResult(stdout: "", status: 127) }
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [first] + argv.dropFirst()
        }
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        var env = ProcessInfo.processInfo.environment
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        env["PAGER"] = "cat"
        env["GIT_PAGER"] = "cat"
        env["PATH"] = Self.searchPath(env["PATH"])
        process.environment = env

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        let outData = DataBox()
        let errData = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            outData.data = out.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errData.data = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        do {
            try process.run()
        } catch {
            return ShellResult(stdout: "", stderr: error.localizedDescription, status: 127)
        }
        let deadline = DispatchTime.now() + timeout
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            process.waitUntilExit()
            finished.signal()
        }
        if finished.wait(timeout: deadline) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 1)
        }
        _ = group.wait(timeout: .now() + 1)
        return ShellResult(
            stdout: String(decoding: outData.data, as: UTF8.self),
            stderr: String(decoding: errData.data, as: UTF8.self),
            status: process.isRunning ? -1 : process.terminationStatus)
    }

    /// Apps started from Finder get a minimal PATH; add the usual tool locations.
    static func searchPath(_ current: String?) -> String {
        let extra = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin"]
        var parts = (current ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        for dir in extra where !parts.contains(dir) { parts.append(dir) }
        return parts.joined(separator: ":")
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}
