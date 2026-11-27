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
- Local network (10/8, 172.16/12, 192.168/16, link-local, multicast, broadcast, IPv6 ULA)
  stays outside the tunnel, the same ranges as the Android app.
- When macOS refuses to start the tunnel or browser filtering, the app shows why, with a button
  to the VPN settings.

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
  query log and today's statistics; `EngineWatchdog` restarts the core when it stops or stops
  taking packets, and gives the tunnel up (the Mac keeps its own network) when it cannot.
- `Shared/` — settings, filter catalog and the app ↔ tunnel messages, compiled into both targets.
- The extension runs as root, so it shares no files with the app. Settings travel in the VPN
  configuration (used when the system starts the tunnel) and in `apply` messages; the newest
  `revision` wins. Quitting the app stops protection and browser filtering; the next launch
  turns protection back on if it was on. The extension keeps running if the app crashes.
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

The app icon is the Android app's design; `swift scripts/make-icon.swift` renders it into
`App/Assets.xcassets`.

A system extension is only replaced when its build number changes. When reinstalling a local
build over one with the same number, build with a higher one, e.g.
`CURRENT_PROJECT_VERSION=2.1`. Do not mix a debug app (Apple Development) with a Developer ID
extension: macOS then refuses to launch the tunnel (code signature requirements).

## Distribution (Developer ID)

`OAB_NE_PROVIDER` in `Config/Base.xcconfig` picks the Network Extension entitlement value:
`packet-tunnel-provider` for Debug (Apple Development profiles only allow this one) and
`packet-tunnel-provider-systemextension` for Release (required by Developer ID profiles).

`scripts/archive.sh` archives a Release build (Apple silicon) with manual signing and exports it
to `build/export/Open AdBlock.app`:

```bash
TEAM_ID=J299H8YWF8 APP_PROFILE="<app profile name>" TUNNEL_PROFILE="<tunnel profile name>" \
    scripts/archive.sh
ditto -c -k --keepParent "build/export/Open AdBlock.app" build/OpenAdBlock.zip
xcrun notarytool submit build/OpenAdBlock.zip --keychain-profile <profile> --wait
xcrun stapler staple "build/export/Open AdBlock.app"
```

### Signed releases (GitHub Actions)

`.github/workflows/build.yml` publishes every push to `main` as the `nightly` pre-release and
every `vX.Y.Z` tag as a release. It signs with Developer ID and notarizes once these secrets
exist; until then the release holds an unsigned build. One-time setup, team Quang Thang To
(`J299H8YWF8`), by its Account Holder:

1. **Certificate.** Xcode › Settings › Accounts › (Apple ID) › Manage Certificates › **+** ›
   *Developer ID Application*. In Keychain Access, export that certificate with its private key
   as `DeveloperID.p12`, protected by a password.
2. **App IDs** (developer.apple.com › Certificates, Identifiers & Profiles › Identifiers):
   `io.github.tothanggtvt.openadblock.mac` with *Network Extensions*, *System Extension* and
   *App Groups*; `io.github.tothanggtvt.openadblock.mac.tunnel` with *Network Extensions* and
   *App Groups*. Xcode already registered both; check the capabilities.
3. **Profiles** › **+** › *Developer ID* (macOS), one per App ID, with the Developer ID
   certificate. Download both `.provisionprofile` files.
4. **Notarization**, either way:
   - *Apple ID*: account.apple.com › Sign-In and Security › App-Specific Passwords › **+**.
     Secrets `NOTARY_APPLE_ID` (the Apple ID's email) and `NOTARY_PASSWORD`.
   - *API key* (needs App Store Connect API access, requested once by the Account Holder):
     App Store Connect › Users and Access › Integrations › Team Keys › **+** (role *Developer*).
     Download `AuthKey_<id>.p8` (only once); secrets `NOTARY_API_KEY` (base64 of the file),
     `NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER_ID`.
5. **Secrets** (`gh secret set NAME` without input asks for the value):

```bash
base64 -i DeveloperID.p12 | gh secret set MACOS_DEVELOPER_ID_P12
gh secret set MACOS_DEVELOPER_ID_P12_PASSWORD
base64 -i <app>.provisionprofile | gh secret set MACOS_APP_PROFILE
base64 -i <tunnel>.provisionprofile | gh secret set MACOS_TUNNEL_PROFILE
gh secret set NOTARY_APPLE_ID
gh secret set NOTARY_PASSWORD
```

Then re-run the workflow (Actions › Build › Run workflow) or push. Pull requests always build
unsigned and never see the secrets.

To remove the extension during development: `systemextensionsctl uninstall <TEAM_ID>
io.github.tothanggtvt.openadblock.mac.tunnel` (or delete the app from /Applications).

## Not yet

- HTTPS filtering (needs a root CA in the user's keychain; the core supports it).
- Per-app rules: packet tunnels do not see which app sent a packet.
- Localisation (Vietnamese), launch at login.
