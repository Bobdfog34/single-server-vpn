# SingleServerVPN (iOS, single embedded server)

iOS VPN app (SwiftUI + `NEPacketTunnelProvider`) with one embedded Xray/VLESS server config. Built in GitHub Actions on macOS runners and packaged as an **unsigned IPA**.

## What's inside

- `Sources/App` — SwiftUI app and `NETunnelProviderManager` integration
- `Sources/PacketTunnel` — Packet Tunnel extension using [SwiftyXrayKit](https://github.com/dima-u/SwiftyXrayKit) / libXray TUN bridge
- `Sources/Shared/Resources/server.json` — embedded server config (from provided JSON; `inbounds` replaced by TUN at runtime)
- `project.yml` — XcodeGen project spec (app + extension + SPM dependency)
- `.github/workflows/build-ipa.yml` — cloud build and unsigned IPA artifact

## Build (GitHub Actions, no Mac required)

1. Create a new **private** GitHub repository and push this project to it (branch `main`).
2. Open **Actions** → **Build unsigned IPA** → **Run workflow** (or push to `main`).
3. Download artifact `SingleServerVPN-unsigned-ipa` (`SingleServerVPN-unsigned.ipa` + `sha256.txt`).

Bundle IDs used:
- App: `com.singleserver.vpn`
- Tunnel: `com.singleserver.vpn.tunnel`
- App Group: `group.com.singleserver.vpn`

## Signing / installation

The produced IPA is unsigned. iOS VPN apps require the **Network Extension (Packet Tunnel)** entitlement for both the app and the extension, so you must sign with an Apple signing identity/profile that has this capability and matching App IDs / App Group.

- With a paid Apple Developer account: create App IDs + App Group, enable Network Extensions, create provisioning profiles, and re-sign the app and appex (e.g. with your usual signing/resign tool) preserving entitlements.
- Free/personal-team signing: Packet Tunnel capability is generally not available for free provisioning; installation may fail or the tunnel may not start.
- Sideloading tools (AltStore/Sideloadly/etc.) can re-sign, but they cannot grant entitlements that your provisioning profile does not include.

## Notes

- Server: `194.55.239.121:443`, VLESS over gRPC/TLS (`it.amplik.net`), with `finalmask` fragment rules as provided.
- TUN inbound/sniffing is injected by the tunnel provider at runtime; routing/DNS/outbounds come from the embedded config.
- This project depends on `SwiftyXrayKit`'s bundled libXray build. If the bundled core does not support gRPC or `finalmask` for your environment, replace the dependency/core with one that does and rebuild.
- Keep this repository private: the server UUID and config are embedded in the app bundle.

## Local regeneration (on macOS)

```bash
brew install xcodegen
xcodegen generate
open SingleServerVPN.xcodeproj
```
