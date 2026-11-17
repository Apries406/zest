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
    private let clientsLock = NSLock()
    private var clients: [String: Client] = [:]

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

    /// 异步生成器与按键回复共用一个串行写入队列，避免协议消息相互穿插。
    public func sendMenu(_ state: CompletionController.State) {
        guard state.terminalMenu else { return }
        clientsLock.lock()
        let client = clients[state.session]
        clientsLock.unlock()
        client?.send(TerminalMenu.format(state))
    }

    private final class Client: @unchecked Sendable {
        let fd: Int32
        private let writer = DispatchQueue(label: "zest.socket.write")
        private var canWrite = true

        init(_ fd: Int32) {
            self.fd = fd
            // 不读取结果的 Shell 不能阻塞其他会话或无限积压写入任务。
            var timeout = timeval(tv_sec: 0, tv_usec: 100_000)
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        }

        func send(_ text: String) {
            writer.async { [self] in
                guard canWrite else { return }
                let bytes = Array(text.utf8)
                bytes.withUnsafeBytes { raw in
                    var offset = 0
                    while offset < raw.count {
                        let n = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                        if n < 0, errno == EINTR { continue }
                        guard n > 0 else {
                            canWrite = false
                            shutdown(fd, SHUT_RDWR)
                            return
                        }
                        offset += n
                    }
                }
            }
        }

        func close() {
            writer.sync {
                canWrite = false
                Darwin.close(fd)
            }
        }
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
        let client = Client(fd)
        var session: String?
        defer {
            clientsLock.lock()
            if let session, clients[session] === client { clients[session] = nil }
            clientsLock.unlock()
            client.close()
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
                if case .hello(let id, _, _, _) = message {
                    clientsLock.lock()
                    if let session, clients[session] === client { clients[session] = nil }
                    session = id
                    clients[id] = client
                    clientsLock.unlock()
                }
                let reply = handler(message)
                if case .key(let sequence, _, _) = message {
                    let text = ShellProtocol.format(reply ?? .pass, sequence: sequence)
                    client.send(text)
                }
            }
            // A runaway client must not grow memory without bound.
            if pending.count > 1 << 20 { return }
        }
    }
}
