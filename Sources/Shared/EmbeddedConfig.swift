import Foundation

enum EmbeddedConfig {
    static var url: URL? {
        Bundle.main.url(forResource: "server", withExtension: "json")
    }

    static var string: String? {
        guard let url else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
