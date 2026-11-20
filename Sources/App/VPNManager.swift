import Foundation
import NetworkExtension

@MainActor
final class VPNManager: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .disconnected
    @Published private(set) var lastError: String?

    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let session = notification.object as? NETunnelProviderSession else { return }
            let newStatus = session.status
            Task { @MainActor in
                self?.status = newStatus
            }
        }
        Task { await load() }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func load() async {
        do {
            let all = try await NETunnelProviderManager.loadAllFromPreferences()
            let existing = all.first { $0.protocolConfiguration is NETunnelProviderProtocol }
            if let existing {
                manager = existing
                status = existing.connection.status
                return
            }
            let created = NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = AppIdentity.tunnelBundleIdentifier
            proto.serverAddress = AppIdentity.serverAddress
            proto.providerConfiguration = ["mode": "embedded"]
            proto.disconnectOnSleep = false
            created.protocolConfiguration = proto
            created.localizedDescription = AppIdentity.displayName
            created.isEnabled = true
            try await created.saveToPreferences()
            try await created.loadFromPreferences()
            manager = created
            status = created.connection.status
        } catch {
            lastError = String(describing: error)
        }
    }

    func connect() async {
        do {
            if manager == nil { await load() }
            guard let manager else { return }
            try await manager.loadFromPreferences()
            try manager.connection.startVPNTunnel()
            status = manager.connection.status
        } catch {
            lastError = String(describing: error)
        }
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
    }

    func clearError() {
        lastError = nil
    }
}
