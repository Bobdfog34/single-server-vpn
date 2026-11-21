import SwiftUI
import NetworkExtension

struct ContentView: View {
    @StateObject private var vpn = VPNManager()
    @StateObject private var geo = GeoDownloadManager()
    @State private var showSettings = false

    private enum Palette {
        static let top = Color(red: 0.04, green: 0.06, blue: 0.16)
        static let bottom = Color(red: 0.15, green: 0.08, blue: 0.30)
        static let accent = Color(red: 0.23, green: 0.74, blue: 0.98)
        static let accentSecondary = Color(red: 0.55, green: 0.36, blue: 0.96)
        static let card = Color.white.opacity(0.08)
        static let stroke = Color.white.opacity(0.12)
    }

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

    private var statusSubtitle: String {
        isConnected ? "Туннель активен" : "Туннель отключён"
    }

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: [Palette.top, Palette.bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                RadialGradient(
                    colors: [Palette.accent.opacity(0.20), Color.clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 320
                )
                .ignoresSafeArea()

                RadialGradient(
                    colors: [Palette.accentSecondary.opacity(0.18), Color.clear],
                    center: .bottomLeading,
                    startRadius: 20,
                    endRadius: 300
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        header
                        statusCard
                        detailsCard
                        geoCard
                        connectButton

                        if let error = vpn.lastError {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(Color.red.opacity(0.9))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }

                        credit
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle(AppIdentity.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView().environmentObject(vpn)
            }
            .onAppear { geo.refresh() }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Palette.accent, Palette.accentSecondary], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 46, height: 46)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Безопасный туннель")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
                Text("Один сервер. Без лишнего.")
                    .font(.headline)
                    .foregroundStyle(Color.white)
            }

            Spacer(minLength: 0)
        }
    }

    private var statusCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    .frame(width: 116, height: 116)

                Circle()
                    .fill(isConnected ? Color.green.opacity(0.28) : Palette.accent.opacity(0.20))
                    .frame(width: 92, height: 92)
                    .blur(radius: 8)

                Circle()
                    .fill(isConnected ? Color.green.opacity(0.22) : Color.white.opacity(0.08))
                    .frame(width: 78, height: 78)

                Image(systemName: isConnected ? "checkmark.shield.fill" : "shield.slash.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(isConnected ? Color.green : Color.white.opacity(0.75))
            }

            Text(statusText)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)

            Text(statusSubtitle)
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.60))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(cardBackground())
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            InfoRow(icon: "server.rack", title: "Сервер", value: AppIdentity.serverAddress, monospaced: true)
            Divider()
                .background(Color.white.opacity(0.10))
                .padding(.leading, 50)
            InfoRow(icon: "network", title: "Транспорт", value: "VLESS / gRPC / TLS")
        }
        .padding(16)
        .background(cardBackground())
    }

    private var geoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Гео-базы", systemImage: "globe.americas.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)

                Spacer()

                Text(geo.isDownloaded ? "Готово" : "Нет файлов")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(geo.isDownloaded ? Color.green.opacity(0.18) : Color.white.opacity(0.10)))
                    .foregroundStyle(geo.isDownloaded ? Color.green : Color.white.opacity(0.65))
            }

            if geo.isDownloading {
                ProgressView(value: geo.progress)
                    .tint(Palette.accent)

                HStack {
                    Text("Загрузка гео-баз…")
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.65))
                    Spacer()
                    Text("\(Int(geo.progress * 100))%")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.80))
                }
            } else {
                Button {
                    Task { await geo.download() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Скачать geo")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(Palette.accent)
                .disabled(isBusy)
            }

            if let error = geo.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Color.red.opacity(0.9))
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .background(cardBackground())
    }

    private var connectButton: some View {
        Button {
            Task {
                if isConnected {
                    vpn.disconnect()
                } else {
                    await vpn.connect()
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isConnected ? "xmark.circle.fill" : "bolt.fill")
                Text(isConnected ? "Отключить" : "Подключить")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(LinearGradient(colors: [Palette.accent, Palette.accentSecondary], startPoint: .leading, endPoint: .trailing))
            .foregroundStyle(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Palette.accent.opacity(0.25), radius: 14, x: 0, y: 8)
        }
        .disabled(isBusy || geo.isDownloading)
        .opacity(isBusy || geo.isDownloading ? 0.6 : 1)
    }

    private var credit: some View {
        Link(destination: AppIdentity.telegramURL) {
            HStack(spacing: 7) {
                Image(systemName: "paperplane.fill")
                Text("Создал @VUral_Gaisin")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.white.opacity(0.62))
            .padding(.vertical, 6)
        }
    }

    private func cardBackground(cornerRadius: CGFloat = 20) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Palette.card)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Palette.stroke, lineWidth: 1)
            )
    }
}

private struct InfoRow: View {
    let icon: String
    let title: String
    let value: String
    var monospaced: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 0.23, green: 0.74, blue: 0.98))
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.55))
                Text(value)
                    .font(monospaced ? .system(size: 14, design: .monospaced) : .system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
            }

            Spacer(minLength: 0)
        }
    }
}
