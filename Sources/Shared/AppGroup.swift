import Foundation

enum AppGroup {
    static let identifier = "group.com.singleserver.vpn"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
