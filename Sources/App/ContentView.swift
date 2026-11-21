import SwiftUI
import NetworkExtension

struct ContentView: View {
    @StateObject private var vpn = VPNManager()
    @StateObject private var geo = GeoDownloadManager()

    private var isConnected: Bool {
        vpn.status == .connected
    }

    private var isBusy: Bool {
        vpn.status == .connecting || vpn.status == .disconnecting || vpn.status == .reasserting
    }

    private var statusText: String {
        switch vpn.status {
        case .invalid: return "Invalid"
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .disconnecting: return "Disconnecting"
        case .reasserting: return "Reconnecting"
        @unknown default: return "Unknown"
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.secondary.opacity(0.35))
                        .frame(width: 22, height: 22)
                    Text(statusText)
                        .font(.title2.weight(.semibold))
                }
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 6) {
                    Label("Server", systemImage: "server.rack")
                    Text(AppIdentity.serverAddress)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Label("Transport", systemImage: "network")
                    Text("VLESS / gRPC / TLS")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 8) {
                    Label("Geo databases", systemImage: "globe")
                    Text(geo.isDownloaded ? "Downloaded" : "Not downloaded")
                        .font(.footnote)
                        .foregroundStyle(geo.isDownloaded ? Color.green : Color.secondary)

                    if geo.isDownloading {
                        ProgressView(value: geo.progress)
                        Text("Downloading \(Int(geo.progress * 100))%")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Download geo") {
                            Task { await geo.download() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isBusy)
                    }

                    if let error = geo.lastError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))

                if let error = vpn.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                Button {
                    Task {
                        if isConnected {
                            vpn.disconnect()
                        } else {
                            await vpn.connect()
                        }
                    }
                } label: {
                    Text(isConnected ? "Disconnect" : "Connect")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || geo.isDownloading)
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle(AppIdentity.displayName)
            .onAppear { geo.refresh() }
        }
    }
}
