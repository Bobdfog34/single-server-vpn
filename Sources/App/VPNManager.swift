import Foundation
import NetworkExtension

@MainActor
final class VPNManager: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .disconnected
    @Published private(set) var lastError: String?
    @Published private(set) var tunnelLog: String?

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
                self?.refreshDiagnostics()
            }
        }
        Task {
            await load()
            refreshDiagnostics()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func load() async {
        do {
            let all = try await NETunnelProviderManager.loadAllFromPreferences()
            if var existing = all.first(where: { $0.protocolConfiguration is NETunnelProviderProtocol }) {
                if !existing.isEnabled {
                    existing.isEnabled = true
                    try await existing.saveToPreferences()
                    try await existing.loadFromPreferences()
                }
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
            lastError = message(for: error)
        }
    }

    func connect() async {
        do {
            if manager == nil { await load() }
            guard var current = manager else { return }
            try await current.loadFromPreferences()
            if !current.isEnabled {
                current.isEnabled = true
                try await current.saveToPreferences()
                try await current.loadFromPreferences()
            }
            manager = current
            TunnelDiagnostics.log("App: connect requested")
            try current.connection.startVPNTunnel()
            status = current.connection.status
        } catch {
            lastError = message(for: error)
            TunnelDiagnostics.log("App connect failed: \(lastError ?? String(describing: error))")
        }
    }

    private func message(for error: Error) -> String {
        if let vpnError = error as? NEVPNError,
           vpnError.code == .configurationDisabled {
            return "VPN configuration is disabled. Enable it in Settings → General → VPN & Device Management."
        }
        return String(describing: error)
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
    }

    func clearError() {
        lastError = nil
    }

    func refreshDiagnostics() {
        let log = TunnelDiagnostics.recent()
        tunnelLog = log.isEmpty ? nil : log
    }
}
