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
        let preferences = VPNConfigurationStore.loadPreferences()
        let profiles = VPNConfigurationStore.loadProfiles()
        let activeProfile = VPNConfigurationStore.activeProfile(preferences: preferences, profiles: profiles)

        guard let config = activeProfile?.configJSON ?? EmbeddedConfig.string else {
            completionHandler(TunnelError.missingConfig)
            return
        }

        do {
            let dataDir = AppGroup.xrayDataURL
            try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
            let finalConfig = dataDir.appendingPathComponent("config.json")
            let remoteAddress = activeProfile?.serverAddress ?? AppIdentity.serverAddress

            setTunnelNetworkSettings(makeNetworkSettings(remoteAddress: remoteAddress, preferences: preferences)) { [weak self] settingsError in
                guard let self else {
                    completionHandler(settingsError)
                    return
                }
                guard settingsError == nil else {
                    completionHandler(settingsError)
                    return
                }
                do {
                    let bridge = XrayBridge(packetFlow: self.packetFlow)
                    try bridge.start(
                        config: .json(config),
                        dataDir: dataDir,
                        finalConfigPath: finalConfig,
                        preset: .mobile,
                        configTransform: { config in
                            var result = config
                            Self.applyPreferences(to: &result, preferences: preferences)
                            return result
                        },
                        traceHandle: { message in
                            NSLog("Xray: %@", message)
                        }
                    )
                    self.bridge = bridge
                    completionHandler(nil)
                } catch {
                    completionHandler(error)
                }
            }
        } catch {
            completionHandler(error)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        bridge?.stop()
        bridge = nil
        completionHandler()
    }

    private func makeNetworkSettings(remoteAddress: String, preferences: VPNPreferences) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: remoteAddress)
        settings.mtu = NSNumber(value: preferences.mtu)

        let ipv4 = NEIPv4Settings(addresses: ["10.131.0.2"], subnetMasks: ["255.255.255.252"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
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
