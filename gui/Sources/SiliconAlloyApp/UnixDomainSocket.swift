import Darwin
import Foundation

enum UnixDomainSocket {
    static func request(path: String, payload: Data) throws -> Data {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        var pathBytes = Array(path.utf8CString)
        if pathBytes.count > MemoryLayout.size(ofValue: address.sun_path) {
            throw SocketError.pathTooLong
        }
        // ensure null-termination
        if pathBytes.last != 0 {
            pathBytes.append(0)
        }

        /*
         * macOS still expects plain posix sockets for this flow, so we wire the fd by hand,
         * double-check the sockaddr_un layout, and guard the lifetime ourselves. it keeps the
         * control surface small and avoids surprising autorelease behavior.
         */
        let sockfd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sockfd >= 0 else {
            throw SocketError.posix(errno)
        }

        defer {
            close(sockfd)
        }

        withUnsafeMutablePointer(to: &address.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { sunPath in
                _ = memcpy(sunPath, pathBytes, pathBytes.count)
            }
        }

        let sockLen = socklen_t(MemoryLayout<sa_family_t>.size + pathBytes.count)
        let result = withUnsafePointer(to: &address) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(sockfd, sockaddrPtr, sockLen)
            }
        }
        guard result == 0 else {
            throw SocketError.posix(errno)
        }

        var message = payload
        message.append(0x0A)
        try message.withUnsafeBytes { buffer in
            try sendAll(sockfd: sockfd, buffer: buffer)
        }

        return try readResponse(sockfd: sockfd)
    }

    private static func sendAll(sockfd: Int32, buffer: UnsafeRawBufferPointer) throws {
        var bytesSent = 0
        while bytesSent < buffer.count {
            let remaining = buffer.count - bytesSent
            let pointer = buffer.baseAddress!.advanced(by: bytesSent)
            let written = write(sockfd, pointer, remaining)
            if written < 0 {
                if errno == EINTR {
                    continue
                }
                throw SocketError.posix(errno)
            }
            bytesSent += written
        }
    }

    private static func readResponse(sockfd: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let readBytes = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
                let pointer = rawBuffer.baseAddress
                return read(sockfd, pointer, rawBuffer.count)
            }
            if readBytes < 0 {
                if errno == EINTR {
                    continue
                }
                throw SocketError.posix(errno)
            }
            if readBytes == 0 {
                break
            }
            data.append(buffer, count: readBytes)
            if data.last == 0x0A {
                break
            }
        }
        if let newlineIndex = data.lastIndex(of: 0x0A) {
            return data.prefix(upTo: newlineIndex)
        }
        return data
    }

    enum SocketError: Error {
        case pathTooLong
        case posix(Int32)

        var localizedDescription: String {
            switch self {
            case .pathTooLong:
                return "socket path is too long"
            case .posix(let code):
                return String(cString: strerror(code))
            }
        }
    }
}

