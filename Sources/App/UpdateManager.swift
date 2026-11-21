import Foundation

@MainActor
final class UpdateManager: ObservableObject {
    @Published private(set) var currentVersion: String
    @Published private(set) var latestVersion: String?
    @Published private(set) var downloadURL: URL? = AppIdentity.releaseAssetURL
    @Published private(set) var isChecking = false
    @Published private(set) var updateAvailable = false
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

    func check() async {
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
        } catch {
            lastError = error.localizedDescription
            updateAvailable = false
        }
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
