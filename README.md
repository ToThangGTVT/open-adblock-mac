# Open AdBlock for macOS

System-wide ad and tracker blocking for macOS, built with SwiftUI and a Network Extension
packet tunnel. The filtering engine is the same Rust core as the
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
SwiftUI app ──settings.json / lists (App Group)──▶ PacketTunnel.appex
     │  sendProviderMessage(status | reload | clearLog)        │
     └───────────────────────────────────────────────────────▶ │ NEPacketTunnelProvider
                                                               │   packetFlow ⇄ NativeEngine.startPackets
                                                               ▼
                                         OpenAdBlockCore (Swift) → libopenadblock (Rust, static)
```

- `App/` — SwiftUI window, menu bar extra, `TunnelManager` (NETunnelProviderManager + polling),
  `SettingsStore` (settings and list downloads).
- `PacketTunnel/` — `PacketTunnelProvider` runs the core in packet mode; `EventStore` keeps the
  query log and today's statistics.
- `Shared/` — settings, filter catalog and the app ↔ tunnel messages, compiled into both targets.
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

Run the app, turn protection on and allow the VPN configuration when macOS asks.

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

## Distribution notes

This is the App Store–style packaging (sandboxed app + app extension). Distributing outside the
Mac App Store with Developer ID requires turning the extension into a system extension
(`packet-tunnel-provider-systemextension`); the provider code stays the same.

## Not yet

- HTTPS filtering (needs a root CA in the user's keychain; the core supports it).
- Per-app rules: packet tunnels do not see which app sent a packet.
- App icon, localisation (Vietnamese), launch at login.
