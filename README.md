# Open AdBlock for macOS

System-wide ad and tracker blocking for macOS, built with SwiftUI and a Network Extension
packet tunnel shipped as a **system extension** (distributable with Developer ID, outside the Mac
App Store). The filtering engine is the same Rust core as the
[Android app](https://github.com/ToThangGTVT/open-adblock):
[open-adblock-core](https://github.com/ToThangGTVT/open-adblock-core), pinned here as a git
submodule on its `main` branch.

## Features

- One switch (window or menu bar) filters DNS for every app on the Mac.
- Encrypted upstream DNS: Cloudflare, Google, AdGuard, Quad9 (DNS-over-HTTPS) or a custom
  UDP/TCP/DoT/DoH/DoQ server.
- Block lists: AdGuard DNS filter (default), StevenBlack hosts, ABPVN; custom rules in
  AdGuard/uBlock syntax (`||ads.example^`, `@@||allowed.example^`).
- Query log with search, today's totals and most blocked domains, traffic counters.
- IPv6 filtering and Goodbye DPI (experimental) toggles.
- Local network (10/8, 192.168/16, link-local, multicast) stays outside the tunnel.

## How it works

```
SwiftUI app (user)                                  system extension (root)
  ExtensionInstaller ── OSSystemExtensionRequest ─▶ io.github…mac.tunnel.systemextension
  TunnelManager ── providerConfiguration{settings} ─▶ NEPacketTunnelProvider
               ── sendProviderMessage(status | apply | updateLists | clearLog) ─▶
                                                       packetFlow ⇄ NativeEngine.startPackets
                                                       FilterLists (downloads, own container)
                                                       ▼
                                     OpenAdBlockCore (Swift) → libopenadblock (Rust, static)
```

- `App/` — SwiftUI window, menu bar extra, `ExtensionInstaller` (activates the system
  extension), `TunnelManager` (NETunnelProviderManager, settings hand-off, status polling),
  `SettingsStore`.
- `PacketTunnel/` — `main.swift` starts system-extension mode; `PacketTunnelProvider` runs the
  core in packet mode; `FilterLists` downloads lists (refreshed daily); `EventStore` keeps the
  query log and today's statistics.
- `Shared/` — settings, filter catalog and the app ↔ tunnel messages, compiled into both targets.
- The extension runs as root, so it shares no files with the app. Settings travel in the VPN
  configuration (used when the system starts the tunnel) and in `apply` messages; the newest
  `revision` wins. The extension keeps running when the app quits or crashes.
- The tunnel answers DNS at `172.19.0.2` / `fdfe:dcba:9876::2`, the virtual addresses the core
  recognises. The extension's own sockets bypass the tunnel and are bound to the physical
  interface.

## Build

Requirements: Xcode 16 or later (project uses synchronized folders), macOS 14+, Rust via rustup
(the toolchain is pinned by the core), an Apple Developer team (Network Extensions need a
provisioning profile with the Packet Tunnel capability and an App Group).

```bash
git clone --recurse-submodules https://github.com/ToThangGTVT/open-adblock-mac.git
cd open-adblock-mac
scripts/build-core.sh                       # Rust core → COpenAdBlock.xcframework
cp Config/Local.xcconfig.example Config/Local.xcconfig   # set DEVELOPMENT_TEAM
open OpenAdBlock.xcodeproj                  # or:
xcodebuild -scheme OpenAdBlock -allowProvisioningUpdates build
```

System extensions only activate from `/Applications`:

```bash
ditto "build/Build/Products/Debug/Open AdBlock.app" "/Applications/Open AdBlock.app"
open "/Applications/Open AdBlock.app"
```

On first launch approve the extension in System Settings › General › Login Items & Extensions
› Network Extensions (the app shows a banner with a shortcut), then turn protection on and allow
the VPN configuration. `systemextensionsctl list` shows the extension's state.

To compile without signing (CI, quick checks):

```bash
xcodebuild -scheme OpenAdBlock -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

### Updating the core

```bash
git submodule update --remote open-adblock-core   # latest main of open-adblock-core
scripts/build-core.sh
git add open-adblock-core && git commit -m "Update open-adblock-core"
```

## Distribution (Developer ID)

`OAB_NE_PROVIDER` in `Config/Base.xcconfig` picks the Network Extension entitlement value:
`packet-tunnel-provider` for Debug (Apple Development profiles only allow this one) and
`packet-tunnel-provider-systemextension` for Release (required by Developer ID profiles).

```bash
xcodebuild -scheme OpenAdBlock -configuration Release -archivePath build/OpenAdBlock.xcarchive \
    -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath build/OpenAdBlock.xcarchive -exportPath build/export \
    -exportOptionsPlist ExportOptions.plist     # method: developer-id
xcrun notarytool submit "build/export/Open AdBlock.app.zip" --keychain-profile <profile> --wait
xcrun stapler staple "build/export/Open AdBlock.app"
```

To remove the extension during development: `systemextensionsctl uninstall <TEAM_ID>
io.github.tothanggtvt.openadblock.mac.tunnel` (or delete the app from /Applications).

## Not yet

- HTTPS filtering (needs a root CA in the user's keychain; the core supports it).
- Per-app rules: packet tunnels do not see which app sent a packet.
- App icon, localisation (Vietnamese), launch at login.
