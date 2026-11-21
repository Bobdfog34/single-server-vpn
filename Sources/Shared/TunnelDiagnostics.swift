import Foundation

enum TunnelDiagnostics {
    private static let lock = NSLock()
    private static let maxCharacters = 20000

    static var logURL: URL {
        AppGroup.xrayDataURL.appendingPathComponent("tunnel.log")
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(at: AppGroup.xrayDataURL, withIntermediateDirectories: true)
            try Data().write(to: logURL, options: .atomic)
        } catch {
        }
    }

    static func log(_ message: String) {
        lock.lock()
        defer { lock.unlock() }

        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        var data = (try? Data(contentsOf: logURL)) ?? Data()
        data.append(contentsOf: line.utf8)
        if data.count > maxCharacters {
            data = Data(data.suffix(maxCharacters))
        }
        try? data.write(to: logURL, options: .atomic)
    }

    static func recent(_ limit: Int = 6000) -> String {
        lock.lock()
        defer { lock.unlock() }

        guard let data = try? Data(contentsOf: logURL),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return String(text.suffix(limit))
    }
}
