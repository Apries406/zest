import Darwin
import Foundation

/// Listens on a Unix socket for zsh sessions. One thread per connected shell.
/// The socket file is only accessible to the current user (mode 0600).
public final class SocketServer: @unchecked Sendable {
    public enum Failure: Error, CustomStringConvertible {
        case pathTooLong(String)
        case system(String, Int32)

        public var description: String {
            switch self {
            case .pathTooLong(let p): return "socket path is too long: \(p)"
            case .system(let call, let code): return "\(call) failed: \(String(cString: strerror(code)))"
            }
        }
    }

    public let path: String
    private let handler: @Sendable (ShellProtocol.Message) -> ShellProtocol.Reply?
    private var listener: Int32 = -1

    public init(path: String, handler: @escaping @Sendable (ShellProtocol.Message) -> ShellProtocol.Reply?) {
        self.path = path
        self.handler = handler
    }

    public func start() throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        unlink(path)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < capacity else { throw Failure.pathTooLong(path) }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: path.utf8)
            raw[path.utf8.count] = 0
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.system("socket", errno) }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw Failure.system("bind", code)
        }
        chmod(path, 0o600)
        guard listen(fd, 32) == 0 else {
            let code = errno
            close(fd)
            throw Failure.system("listen", code)
        }
        listener = fd

        let thread = Thread { [weak self] in self?.acceptLoop(fd) }
        thread.name = "zest.socket.accept"
        thread.start()
    }

    public func stop() {
        if listener >= 0 {
            close(listener)
            listener = -1
        }
        unlink(path)
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            let thread = Thread { [weak self] in self?.serve(client) }
            thread.name = "zest.socket.client"
            thread.stackSize = 256 * 1024
            thread.start()
        }
    }

    private func serve(_ fd: Int32) {
        var session: String?
        defer {
            close(fd)
            if let session { _ = handler(.disconnected(session: session)) }
        }
        var pending = [UInt8]()
        var chunk = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { return }
            pending.append(contentsOf: chunk[0..<n])
            while let newline = pending.firstIndex(of: 10) {
                let line = String(decoding: pending[0..<newline], as: UTF8.self)
                pending.removeSubrange(0...newline)
                guard let message = ShellProtocol.parse(Substring(line)) else { continue }
                if case .hello(let id, _, _, _) = message { session = id }
                let reply = handler(message)
                if case .key(let sequence, _, _) = message {
                    let text = ShellProtocol.format(reply ?? .pass, sequence: sequence)
                    let bytes = Array(text.utf8)
                    _ = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
                }
            }
            // A runaway client must not grow memory without bound.
            if pending.count > 1 << 20 { return }
        }
    }
}
