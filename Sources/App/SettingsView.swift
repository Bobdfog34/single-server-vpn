import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var subscriptionInput = ""
    @Published var profiles: [VPNProfile] = []
    @Published var preferences = VPNPreferences()
    @Published var isImporting = false
    @Published var message: String?
    @Published var errorText: String?

    init() {
        reload()
    }

    func reload() {
        profiles = VPNConfigurationStore.loadProfiles()
        preferences = VPNConfigurationStore.loadPreferences()
    }

    func importSubscription() async {
        let input = subscriptionInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            errorText = "Введите ссылку подписки или подпись"
            return
        }

        isImporting = true
        errorText = nil
        message = nil

        do {
            let imported = try await SubscriptionImporter.importProfiles(from: input)
            var updated = profiles
            updated.append(contentsOf: imported)
            try VPNConfigurationStore.saveProfiles(updated)
            if preferences.activeProfileID == nil, let first = imported.first {
                preferences.activeProfileID = first.id
                try VPNConfigurationStore.savePreferences(preferences)
            }
            profiles = updated
            subscriptionInput = ""
            message = "Добавлено профилей: \(imported.count)"
        } catch {
            errorText = error.localizedDescription
        }

        isImporting = false
    }

    func select(_ profile: VPNProfile) throws {
        preferences.activeProfileID = profile.id
        try VPNConfigurationStore.savePreferences(preferences)
        message = "Активный профиль: \(profile.name)"
    }

    func delete(_ id: UUID) throws {
        profiles.removeAll { $0.id == id }
        try VPNConfigurationStore.saveProfiles(profiles)
        if preferences.activeProfileID == id {
            preferences.activeProfileID = profiles.first?.id
            try VPNConfigurationStore.savePreferences(preferences)
        }
        message = "Профиль удалён"
    }

    func savePreferences() throws {
        if preferences.dnsServers.isEmpty {
            preferences.dnsServers = ["1.1.1.1", "1.0.0.1"]
        }
        try VPNConfigurationStore.savePreferences(preferences)
        message = "Настройки сохранены"
    }

    func reset() throws {
        try VPNConfigurationStore.reset()
        reload()
        message = "Встроенный сервер восстановлен"
    }
}

struct SettingsView: View {
    @EnvironmentObject private var vpn: VPNManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = SettingsViewModel()

    private enum Palette {
        static let top = Color(red: 0.04, green: 0.06, blue: 0.16)
        static let bottom = Color(red: 0.15, green: 0.08, blue: 0.30)
        static let accent = Color(red: 0.23, green: 0.74, blue: 0.98)
        static let accentSecondary = Color(red: 0.55, green: 0.36, blue: 0.96)
        static let card = Color.white.opacity(0.08)
        static let stroke = Color.white.opacity(0.12)
    }

    private var dnsBinding: Binding<String> {
        Binding(
            get: { model.preferences.dnsServers.joined(separator: ", ") },
            set: { value in
                model.preferences.dnsServers = value
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(colors: [Palette.top, Palette.bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        section(title: "Подписка") {
                            TextField("vless://… или https://site.com/sub", text: $model.subscriptionInput)
                                .textFieldStyle(.plain)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .padding(12)
                                .background(fieldBackground)

                            Button {
                                Task {
                                    await model.importSubscription()
                                    await reconnectIfNeeded()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if model.isImporting {
                                        ProgressView()
                                    }
                                    Text(model.isImporting ? "Загрузка…" : "Импортировать подписку")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                            }
                            .buttonStyle(.bordered)
                            .tint(Palette.accent)
                            .disabled(model.isImporting)

                            Text("Поддерживаются VLESS, VMess и ссылки на подписки с base64-списком.")
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.50))
                        }

                        section(title: "Профили") {
                            if model.profiles.isEmpty {
                                Text("Нет сохранённых профилей. Добавьте подписку выше.")
                                    .font(.footnote)
                                    .foregroundStyle(Color.white.opacity(0.55))
                            } else {
                                ForEach(model.profiles) { profile in
                                    profileRow(profile)
                                }
                            }
                        }

                        section(title: "Настройки") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("DNS-серверы")
                                    .font(.caption)
                                    .foregroundStyle(Color.white.opacity(0.55))
                                TextField("1.1.1.1, 1.0.0.1", text: dnsBinding)
                                    .textFieldStyle(.plain)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .padding(12)
                                    .background(fieldBackground)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("MTU")
                                    .font(.caption)
                                    .foregroundStyle(Color.white.opacity(0.55))
                                Picker("MTU", selection: $model.preferences.mtu) {
                                    ForEach([1280, 1360, 1400, 1500], id: \.self) { value in
                                        Text("\(value)").tag(value)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            Toggle("Использовать geo-базы", isOn: $model.preferences.useGeoDatabases)
                            Toggle("Sniffing трафика", isOn: $model.preferences.sniffingEnabled)

                            Button {
                                Task {
                                    do {
                                        try model.savePreferences()
                                        await reconnectIfNeeded()
                                    } catch {
                                        model.errorText = error.localizedDescription
                                    }
                                }
                            } label: {
                                Text("Сохранить настройки")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Palette.accent)
                        }

                        Button {
                            Task {
                                do {
                                    try model.reset()
                                    await reconnectIfNeeded()
                                } catch {
                                    model.errorText = error.localizedDescription
                                }
                            }
                        } label: {
                            Text("Сбросить на встроенный сервер")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.red.opacity(0.85))

                        if let message = model.message {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(Color.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let error = model.errorText {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(Color.red.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Подписки и настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Готово") { dismiss() }
            }
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground())
    }

    private func profileRow(_ profile: VPNProfile) -> some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    do {
                        try model.select(profile)
                        await reconnectIfNeeded()
                    } catch {
                        model.errorText = error.localizedDescription
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: model.preferences.activeProfileID == profile.id ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(model.preferences.activeProfileID == profile.id ? Color.green : Color.white.opacity(0.40))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                        Text(profile.serverAddress)
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            Button {
                Task {
                    do {
                        try model.delete(profile.id)
                        await reconnectIfNeeded()
                    } catch {
                        model.errorText = error.localizedDescription
                    }
                }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Color.red.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(model.preferences.activeProfileID == profile.id ? Color.green.opacity(0.10) : Color.white.opacity(0.06))
        )
    }

    private func reconnectIfNeeded() async {
        guard vpn.status == .connected else { return }
        vpn.disconnect()
        try? await Task.sleep(nanoseconds: 700_000_000)
        await vpn.connect()
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Palette.stroke, lineWidth: 1)
            )
    }

    private func cardBackground() -> some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Palette.card)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Palette.stroke, lineWidth: 1)
            )
    }
}
