import Darwin
import Foundation

// Сокет в /tmp, а не в TMPDIR: путь должен влезть в sockaddr_un (~104 байта), у macOS TMPDIR длиннее.
enum CommandSocket {
    static func path() -> String {
        "/tmp/appring-\(getuid()).sock"
    }

    static func send(_ line: String) -> Bool {
        let path = self.path()
        var info = stat()
        guard lstat(path, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFSOCK else {
            return false
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_un()
        guard fill(&address, path: path) else { return false }
        let connected = withSockAddress(&address) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        guard connected == 0 else { return false }
        let bytes = Array((line + "\n").utf8)
        let wrote = bytes.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return -1 }
            return write(fd, base, raw.count)
        }
        return wrote == bytes.count
    }

    // run и open часто стартуют вместе. Коротко ждем сокет, и только потом становимся вторым экземпляром.
    static func sendReady(_ line: String) -> Bool {
        for _ in 0..<30 {
            if send(line) { return true }
            usleep(50_000)
        }
        return false
    }
}

final class CommandServer {
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    var onLine: ((String) -> Void)?

    func start() -> Bool {
        let path = CommandSocket.path()
        // Живой сокет не удаляем: иначе второй `appring open` срывает команду у уже запущенного.
        if CommandSocket.send("ping") { return false }
        var info = stat()
        if lstat(path, &info) == 0 {
            guard info.st_uid == getuid() else { return false }
            fputs("appring: replacing stale socket\n", stderr)
            unlink(path)
        }
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        var address = sockaddr_un()
        guard fill(&address, path: path) else { return false }
        let bound = withSockAddress(&address) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        guard bound == 0 else { return false }
        chmod(path, 0o600)
        guard listen(fd, 8) == 0 else { return false }
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        let reader = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        reader.setEventHandler { [weak self] in self?.acceptClients() }
        reader.resume()
        source = reader
        return true
    }

    func stop() {
        source?.cancel()
        source = nil
        // Клиент тоже получает terminate и не должен сносить сокет работающего экземпляра.
        let ownsSocket = fd >= 0
        if fd >= 0 { close(fd) }
        fd = -1
        if ownsSocket { unlink(CommandSocket.path()) }
    }

    private func acceptClients() {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 { return }
            var uid: uid_t = 0
            var gid: gid_t = 0
            if getpeereid(client, &uid, &gid) != 0 || uid != getuid() {
                close(client)
                continue
            }
            var buffer = [UInt8](repeating: 0, count: 512)
            let count = read(client, &buffer, buffer.count)
            close(client)
            guard count > 0 else { continue }
            let line = String(decoding: buffer.prefix(count), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            onLine?(line)
        }
    }
}

private func fill(_ address: inout sockaddr_un, path: String) -> Bool {
    address.sun_family = sa_family_t(AF_UNIX)
    let encoded = Array(path.utf8)
    return withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        guard encoded.count + 1 <= buffer.count else { return false }
        buffer.initializeMemory(as: UInt8.self, repeating: 0)
        for (index, byte) in encoded.enumerated() {
            buffer[index] = byte
        }
        return true
    }
}

private func withSockAddress<T>(_ address: inout sockaddr_un, _ body: (UnsafePointer<sockaddr>) -> T) -> T {
    withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1, body)
    }
}
