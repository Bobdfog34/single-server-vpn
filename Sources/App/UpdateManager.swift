import Foundation

@MainActor
final class UpdateManager: ObservableObject {
    @Published private(set) var currentVersion: String
    @Published private(set) var latestVersion: String?
    @Published private(set) var downloadURL: URL? = AppIdentity.releaseAssetURL
    @Published private(set) var isChecking = false
    @Published private(set) var isDownloading = false
    @Published private(set) var updateAvailable = false
    @Published private(set) var downloadedFileURL: URL?
    @Published private(set) var downloadedVersion: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastError: String?

    private struct Release: Decodable {
        let tag_name: String
        let assets: [Asset]
    }

    private struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
    }

    private enum UpdateError: LocalizedError {
        case badResponse(Int)
        case noReleases

        var errorDescription: String? {
            switch self {
            case .badResponse(let code): return "GitHub вернул ошибку \(code)"
            case .noReleases: return "Релизы не найдены"
            }
        }
    }

    init() {
        currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    func check(autoDownload: Bool = true) async {
        isChecking = true
        lastError = nil
        defer { isChecking = false }

        do {
            var request = URLRequest(url: AppIdentity.releasesAPIURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw UpdateError.badResponse(-1)
            }
            guard (200..<300).contains(http.statusCode) else {
                throw UpdateError.badResponse(http.statusCode)
            }

            let releases = try JSONDecoder().decode([Release].self, from: data)
            guard let release = releases.first else {
                throw UpdateError.noReleases
            }

            latestVersion = Self.normalize(release.tag_name)
            downloadURL = release.assets
                .first(where: { $0.name == "SingleServerVPN-unsigned.ipa" })?
                .browser_download_url ?? AppIdentity.releaseAssetURL
            updateAvailable = Self.compare(latestVersion ?? "", currentVersion) > 0

            if let latestVersion, let existing = Self.existingDownload(for: latestVersion) {
                downloadedFileURL = existing
                downloadedVersion = latestVersion
                statusMessage = "Обновление \(latestVersion) уже скачано"
            }

            if autoDownload && updateAvailable && downloadedFileURL == nil {
                await downloadUpdate()
            }
        } catch {
            lastError = error.localizedDescription
            updateAvailable = false
        }
    }

    func downloadUpdate() async {
        guard let url = downloadURL, let version = latestVersion else { return }
        guard !isDownloading else { return }

        isDownloading = true
        statusMessage = "Скачиваю обновление \(version)…"
        lastError = nil
        defer { isDownloading = false }

        do {
            guard let updatesDir = try? Self.updatesDirectory() else {
                throw UpdateError.noReleases
            }
            let destination = updatesDir.appendingPathComponent("SingleServerVPN-\(version).ipa")
            try? FileManager.default.removeItem(at: destination)

            let (temporaryURL, _) = try await URLSession.shared.download(from: url)
            try FileManager.default.moveItem(at: temporaryURL, to: destination)

            downloadedFileURL = destination
            downloadedVersion = version
            statusMessage = "Обновление \(version) скачано. Поделитесь файлом, чтобы установить."
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Не удалось скачать обновление"
        }
    }

    private static func updatesDirectory() throws -> URL {
        let base = AppGroup.containerURL
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func existingDownload(for version: String) -> URL? {
        guard let directory = try? updatesDirectory() else { return nil }
        let file = directory.appendingPathComponent("SingleServerVPN-\(version).ipa")
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    private static func compare(_ lhs: String, _ rhs: String) -> Int {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l > r ? 1 : -1 }
        }
        return 0
    }
}
