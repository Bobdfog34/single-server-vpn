import Foundation
import NetworkExtension
import SwiftyXrayKit

enum TunnelError: LocalizedError {
    case missingConfig

    var errorDescription: String? {
        switch self {
        case .missingConfig: return "Embedded server config not found"
        }
    }
}

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var bridge: XrayBridge?

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        TunnelDiagnostics.reset()

        let preferences = VPNConfigurationStore.loadPreferences()
        let profiles = VPNConfigurationStore.loadProfiles()
        let activeProfile = VPNConfigurationStore.activeProfile(preferences: preferences, profiles: profiles)
        let configJSON = activeProfile?.configJSON ?? EmbeddedConfig.string

        TunnelDiagnostics.log("Start: profile=\(activeProfile?.name ?? "embedded"), sniffing=\(preferences.sniffingEnabled), geo=\(preferences.useGeoDatabases)")

        guard !configJSON.isEmpty else {
            TunnelDiagnostics.log("Start failed: missing config")
            completionHandler(TunnelError.missingConfig)
            return
        }

        setTunnelNetworkSettings(makeNetworkSettings(preferences: preferences)) { [weak self] settingsError in
            guard let self else {
                completionHandler(settingsError)
                return
            }
            if let settingsError {
                TunnelDiagnostics.log("Network settings failed: \(String(describing: settingsError))")
                completionHandler(settingsError)
                return
            }

            TunnelDiagnostics.log("Network settings applied")
            self.startBridge(configJSON: configJSON, preferences: preferences, finalName: "config.json") { primaryError in
                guard let primaryError else {
                    completionHandler(nil)
                    return
                }
                TunnelDiagnostics.log("Primary start failed: \(String(describing: primaryError))")

                guard let safeConfig = Self.safeConfig(from: configJSON) else {
                    completionHandler(primaryError)
                    return
                }
                var safePreferences = preferences
                safePreferences.sniffingEnabled = false
                TunnelDiagnostics.log("Retrying with safe config")

                self.startBridge(configJSON: safeConfig, preferences: safePreferences, finalName: "config_safe.json") { fallbackError in
                    if let fallbackError {
                        TunnelDiagnostics.log("Safe start failed: \(String(describing: fallbackError))")
                    } else {
                        TunnelDiagnostics.log("Safe start succeeded")
                    }
                    completionHandler(fallbackError)
                }
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        TunnelDiagnostics.log("Stop reason: \(reason.rawValue)")
        bridge?.stop()
        bridge = nil
        completionHandler()
    }

    private func startBridge(
        configJSON: String,
        preferences: VPNPreferences,
        finalName: String,
        completion: @escaping (Error?) -> Void
    ) {
        do {
            let dataDir = AppGroup.xrayDataURL
            try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
            let finalConfig = dataDir.appendingPathComponent(finalName)
            let bridge = XrayBridge(packetFlow: packetFlow)
            try bridge.start(
                config: .json(configJSON),
                dataDir: dataDir,
                finalConfigPath: finalConfig,
                preset: .mobile,
                configTransform: { config in
                    var result = config
                    Self.applyPreferences(to: &result, preferences: preferences)
                    return result
                },
                traceHandle: { message in
                    TunnelDiagnostics.log("Xray: \(message)")
                }
            )
            self.bridge = bridge
            completion(nil)
        } catch {
            completion(error)
        }
    }

    private static func safeConfig(from json: String) -> String? {
        guard let data = json.data(using: .utf8),
              var config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if var outbounds = config["outbounds"] as? [[String: Any]] {
            for index in outbounds.indices {
                guard var stream = outbounds[index]["streamSettings"] as? [String: Any] else { continue }
                stream.removeValue(forKey: "finalmask")
                if var sockopt = stream["sockopt"] as? [String: Any] {
                    sockopt["tcpFastOpen"] = false
                    stream["sockopt"] = sockopt
                }
                outbounds[index]["streamSettings"] = stream
            }
            config["outbounds"] = outbounds
        }

        var log = config["log"] as? [String: Any] ?? [:]
        log["loglevel"] = "debug"
        config["log"] = log

        guard let output = try? JSONSerialization.data(withJSONObject: config, options: .prettyPrinted) else {
            return nil
        }
        return String(data: output, encoding: .utf8)
    }

    private func makeNetworkSettings(preferences: VPNPreferences) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.mtu = NSNumber(value: preferences.mtu)

        let ipv4 = NEIPv4Settings(addresses: ["10.131.0.2"], subnetMasks: ["255.255.255.252"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        ipv4.excludedRoutes = [
            NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
            NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"),
            NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
            NEIPv4Route(destinationAddress: "169.254.0.0", subnetMask: "255.255.0.0")
        ]
        settings.ipv4Settings = ipv4

        let servers = preferences.dnsServers.isEmpty ? ["1.1.1.1", "1.0.0.1"] : preferences.dnsServers
        let dns = NEDNSSettings(servers: servers)
        dns.matchDomains = [""]
        settings.dnsSettings = dns

        return settings
    }

    private static func applyPreferences(to config: inout [String: Any], preferences: VPNPreferences) {
        var dns = config["dns"] as? [String: Any] ?? [:]
        dns["servers"] = preferences.dnsServers.isEmpty ? ["1.1.1.1", "1.0.0.1"] : preferences.dnsServers
        config["dns"] = dns

        if var inbounds = config["inbounds"] as? [[String: Any]], !inbounds.isEmpty {
            if var inboundSettings = inbounds[0]["settings"] as? [String: Any] {
                inboundSettings["MTU"] = preferences.mtu
                inbounds[0]["settings"] = inboundSettings
            }
            if preferences.sniffingEnabled {
                inbounds[0]["sniffing"] = [
                    "enabled": true,
                    "routeOnly": false,
                    "destOverride": ["http", "tls", "quic"]
                ]
            } else {
                inbounds[0].removeValue(forKey: "sniffing")
            }
            config["inbounds"] = inbounds
        }

        guard !preferences.useGeoDatabases,
              var routing = config["routing"] as? [String: Any],
              var rules = routing["rules"] as? [[String: Any]] else {
            return
        }

        rules = rules.filter { rule in
            let domains = rule["domain"] as? [String] ?? []
            let ips = rule["ip"] as? [String] ?? []
            let isGeo = domains.contains { $0.hasPrefix("geoip:") || $0.hasPrefix("geosite:") } ||
                        ips.contains { $0.hasPrefix("geoip:") || $0.hasPrefix("geosite:") }
            return !isGeo
        }
        routing["rules"] = rules
        config["routing"] = routing
    }
}
