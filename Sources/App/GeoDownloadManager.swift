import Foundation
import SwiftyXrayKit

@MainActor
final class GeoDownloadManager: ObservableObject {
    @Published private(set) var isDownloading = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var isDownloaded = false
    @Published private(set) var lastError: String?

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
            let loader = GeoFilesLoader()
            try await loader.loadGeoFiles(
                into: dataDir,
                geoSiteURL: nil,
                geoIPURL: nil
            ) { [weak self] value in
                Task { @MainActor in self?.progress = value }
            }
            refresh()
        } catch {
            lastError = String(describing: error)
        }

        isDownloading = false
    }
}
