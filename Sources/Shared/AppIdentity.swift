import Foundation

enum AppIdentity {
    static let tunnelBundleIdentifier = "com.singleserver.vpn.tunnel"
    static let serverAddress = "194.55.239.121"
    static let displayName = "Single Server VPN"
    static let telegramURL = URL(string: "https://t.me/VUral_Gaisin")!
    static let releasesAPIURL = URL(string: "https://api.github.com/repos/Bobdfog34/single-server-vpn/releases?per_page=1")!
    static let releasesPageURL = URL(string: "https://github.com/Bobdfog34/single-server-vpn/releases")!
    static let releaseAssetURL = URL(string: "https://github.com/Bobdfog34/single-server-vpn/releases/download/v1.1.1/SingleServerVPN-unsigned.ipa")!
}
