import Foundation

enum AppGroup {
    static let identifier = "group.com.singleserver.vpn"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var xrayDataURL: URL {
        let base = containerURL
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("xray", isDirectory: true)
    }
}
