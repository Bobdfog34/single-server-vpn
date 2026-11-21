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
        guard let config = EmbeddedConfig.string else {
            completionHandler(TunnelError.missingConfig)
            return
        }

        do {
            let dataDir = AppGroup.xrayDataURL
            try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
            let finalConfig = dataDir.appendingPathComponent("config.json")

            setTunnelNetworkSettings(makeNetworkSettings()) { [weak self] settingsError in
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
                            guard var inbounds = result["inbounds"] as? [[String: Any]],
                                  !inbounds.isEmpty else { return result }
                            inbounds[0]["sniffing"] = [
                                "enabled": true,
                                "routeOnly": false,
                                "destOverride": ["http", "tls", "quic"]
                            ]
                            result["inbounds"] = inbounds
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

    private func makeNetworkSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: AppIdentity.serverAddress)
        settings.mtu = 1360

        let ipv4 = NEIPv4Settings(addresses: ["10.131.0.2"], subnetMasks: ["255.255.255.252"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4

        let dns = NEDNSSettings(servers: ["1.1.1.1", "1.0.0.1"])
        dns.matchDomains = [""]
        settings.dnsSettings = dns

        return settings
    }
}
