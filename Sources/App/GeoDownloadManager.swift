import Foundation

enum GeoDownloadError: LocalizedError {
    case badResponse

    var errorDescription: String? {
        switch self {
        case .badResponse: return "Invalid response from geo database server"
        }
    }
}

@MainActor
final class GeoDownloadManager: ObservableObject {
    @Published private(set) var isDownloading = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var isDownloaded = false
    @Published private(set) var lastError: String?

    private let geoIPURL = URL(string: "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat")!
    private let geoSiteURL = URL(string: "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat")!

    private var dataDir: URL { AppGroup.xrayDataURL }

    func refresh() {
        let fileManager = FileManager.default
        isDownloaded =
            fileManager.fileExists(atPath: dataDir.appendingPathComponent("geoip.dat").path) &&
            fileManager.fileExists(atPath: dataDir.appendingPathComponent("geosite.dat").path)
    }

    func download() async {
        guard !isDownloading else { return }
        isDownloading = true
        progress = 0
        lastError = nil

        do {
            try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
            let geoIPDestination = dataDir.appendingPathComponent("geoip.dat")
            let geoSiteDestination = dataDir.appendingPathComponent("geosite.dat")

            async let downloadGeoIP: Void = download(from: geoIPURL, to: geoIPDestination)
            async let downloadGeoSite: Void = download(from: geoSiteURL, to: geoSiteDestination)

            try await downloadGeoIP
            progress = 0.5
            try await downloadGeoSite
            progress = 1
            refresh()
        } catch {
            lastError = String(describing: error)
        }

        isDownloading = false
    }

    private func download(from url: URL, to destination: URL) async throws {
        try? FileManager.default.removeItem(at: destination)
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GeoDownloadError.badResponse
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }
}
