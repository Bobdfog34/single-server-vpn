import Foundation

struct VPNPreferences: Codable {
    var dnsServers: [String] = ["1.1.1.1", "1.0.0.1"]
    var mtu: Int = 1360
    var useGeoDatabases: Bool = false
    var sniffingEnabled: Bool = true
    var activeProfileID: UUID?
}
