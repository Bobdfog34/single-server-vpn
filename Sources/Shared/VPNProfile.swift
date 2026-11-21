import Foundation

struct VPNProfile: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var serverAddress: String
    var configJSON: String
    var source: String
}
