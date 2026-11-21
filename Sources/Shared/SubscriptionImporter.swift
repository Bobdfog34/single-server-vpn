import Foundation

enum SubscriptionImportError: LocalizedError {
    case empty
    case badResponse
    case unsupported
    case invalidConfig

    var errorDescription: String? {
        switch self {
        case .empty: return "Введите ссылку подписки или подпись"
        case .badResponse: return "Не удалось загрузить подписку"
        case .unsupported: return "Не найдено поддерживаемых VLESS/VMess подписей"
        case .invalidConfig: return "Не удалось собрать конфигурацию"
        }
    }
}

enum SubscriptionImporter {
    static func importProfiles(from input: String) async throws -> [VPNProfile] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SubscriptionImportError.empty }

        var text = trimmed
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            guard let url = URL(string: trimmed) else { throw SubscriptionImportError.badResponse }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw SubscriptionImportError.badResponse
            }
            text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        }

        var links = text
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        if links.count == 1, !links[0].contains("://"), let decoded = decodeBase64(links[0]) {
            links = decoded
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)
        }

        let profiles = links.compactMap { link -> VPNProfile? in
            guard let parsed = parseLink(link) else { return nil }
            return try? makeProfile(name: parsed.1, outbound: parsed.0, source: trimmed)
        }

        guard !profiles.isEmpty else { throw SubscriptionImportError.unsupported }
        return profiles
    }

    private static func parseLink(_ link: String) -> ([String: Any], String, String)? {
        let lower = link.lowercased()
        if lower.hasPrefix("vless://") {
            return parseVLESS(link)
        }
        if lower.hasPrefix("vmess://") {
            return parseVMess(link)
        }
        return nil
    }

    private static func parseVLESS(_ link: String) -> ([String: Any], String, String)? {
        guard let components = URLComponents(string: link),
              components.scheme?.lowercased() == "vless",
              let uuid = components.user,
              let host = components.host else {
            return nil
        }

        let query = queryMap(components)
        let portString = query["port"] ?? components.port.map(String.init) ?? ""
        let port = Int(portString) ?? 443
        let name = components.fragment?.removingPercentEncoding ?? host

        let user: [String: Any] = [
            "id": uuid,
            "encryption": query["encryption"] ?? "none",
            "flow": query["flow"] ?? ""
        ]
        let outbound: [String: Any] = [
            "tag": "proxy",
            "protocol": "vless",
            "settings": ["vnext": [["address": host, "port": port, "users": [user]]]],
            "streamSettings": streamSettings(query: query, host: host)
        ]
        return (outbound, name, host)
    }

    private static func parseVMess(_ link: String) -> ([String: Any], String, String)? {
        let payload = String(link.dropFirst("vmess://".count))
        guard let decoded = decodeBase64(payload),
              let data = decoded.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data),
              let object = raw as? [String: Any],
              let host = stringValue(object["add"]),
              let uuid = stringValue(object["id"]) else {
            return nil
        }

        let port = Int(stringValue(object["port"]) ?? "443") ?? 443
        let name = stringValue(object["ps"]) ?? host
        let query: [String: String] = [
            "type": stringValue(object["net"]) ?? "tcp",
            "security": stringValue(object["tls"]) == "tls" ? "tls" : "none",
            "host": stringValue(object["host"]) ?? host,
            "path": stringValue(object["path"]) ?? "/",
            "sni": stringValue(object["sni"]) ?? host
        ]

        let user: [String: Any] = [
            "id": uuid,
            "aid": Int(stringValue(object["aid"]) ?? "0") ?? 0,
            "security": stringValue(object["scy"]) ?? "auto"
        ]
        let outbound: [String: Any] = [
            "tag": "proxy",
            "protocol": "vmess",
            "settings": ["vnext": [["address": host, "port": port, "users": [user]]]],
            "streamSettings": streamSettings(query: query, host: host)
        ]
        return (outbound, name, host)
    }

    private static func makeProfile(name: String, outbound: [String: Any], source: String) throws -> VPNProfile {
        guard let settings = outbound["settings"] as? [String: Any],
              let vnext = settings["vnext"] as? [[String: Any]],
              let first = vnext.first,
              let address = first["address"] as? String else {
            throw SubscriptionImportError.invalidConfig
        }
        return VPNProfile(
            id: UUID(),
            name: name,
            serverAddress: address,
            configJSON: try buildConfig(outbound: outbound),
            source: source
        )
    }

    private static func buildConfig(outbound: [String: Any]) throws -> String {
        guard let base = EmbeddedConfig.string,
              let baseData = base.data(using: .utf8),
              var config = try JSONSerialization.jsonObject(with: baseData) as? [String: Any],
              var outbounds = config["outbounds"] as? [[String: Any]],
              !outbounds.isEmpty else {
            throw SubscriptionImportError.invalidConfig
        }
        outbounds[0] = outbound
        config["outbounds"] = outbounds
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw SubscriptionImportError.invalidConfig
        }
        return json
    }

    private static func streamSettings(query: [String: String], host: String) -> [String: Any] {
        let network = query["type"] ?? "tcp"
        let security = query["security"] ?? "none"
        var stream: [String: Any] = ["network": network, "security": security]
        let sni = query["sni"] ?? query["host"] ?? host

        if security == "tls" || security == "reality" {
            var tls: [String: Any] = ["serverName": sni]
            if let fingerprint = query["fp"] {
                tls["fingerprint"] = fingerprint
            }
            if let alpn = query["alpn"] {
                tls["alpn"] = alpn.split(separator: ",").map(String.init)
            }
            if security == "reality" {
                tls["publicKey"] = query["pbk"] ?? ""
                tls["shortId"] = query["sid"] ?? ""
            }
            stream[security == "tls" ? "tlsSettings" : "realitySettings"] = tls
        }

        switch network {
        case "grpc":
            stream["grpcSettings"] = [
                "serviceName": query["serviceName"] ?? query["path"] ?? "",
                "authority": query["host"] ?? sni
            ]
        case "ws":
            stream["wsSettings"] = [
                "path": query["path"] ?? "/",
                "headers": ["Host": query["host"] ?? host]
            ]
        case "h2", "http":
            stream["httpSettings"] = [
                "host": (query["host"] ?? host).split(separator: ",").map(String.init),
                "path": query["path"] ?? "/"
            ]
        default:
            stream["tcpSettings"] = ["header": ["type": query["headerType"] ?? "none"]]
        }

        return stream
    }

    private static func queryMap(_ components: URLComponents) -> [String: String] {
        var result: [String: String] = [:]
        for item in components.queryItems ?? [] {
            if let value = item.value {
                result[item.name.lowercased()] = value
            }
        }
        return result
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String {
            return value
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private static func decodeBase64(_ raw: String) -> String? {
        let cleaned = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = cleaned.count % 4
        let padded = remainder == 0 ? cleaned : cleaned + String(repeating: "=", count: 4 - remainder)
        guard let data = Data(base64Encoded: padded) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
