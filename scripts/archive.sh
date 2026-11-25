#!/usr/bin/env bash
# Archives the app (Release) with manual signing and exports it. Used by CI for signed releases;
# runs locally too. The core must be built first (scripts/build-core.sh).
#
# Env:
#   TEAM_ID            Apple team (J299H8YWF8)
#   APP_PROFILE        name of the app's provisioning profile (installed)
#   TUNNEL_PROFILE     name of the system extension's provisioning profile (installed)
#   IDENTITY           signing identity (default "Developer ID Application")
#   EXPORT_METHOD      developer-id (default) or debugging
#   VERSION, BUILD     optional MARKETING_VERSION / CURRENT_PROJECT_VERSION overrides
#   EXTRA_SETTINGS     optional extra build settings (space separated)
# Output: build/export/Open AdBlock.app
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
: "${TEAM_ID:?}" "${APP_PROFILE:?}" "${TUNNEL_PROFILE:?}"
IDENTITY="${IDENTITY:-Developer ID Application}"
EXPORT_METHOD="${EXPORT_METHOD:-developer-id}"
BUNDLE_PREFIX="$(sed -n 's/^OAB_BUNDLE_PREFIX = //p' Config/Base.xcconfig)"

settings=(
    # Apple silicon only: the core is built for aarch64-apple-darwin.
    ARCHS=arm64
    DEVELOPMENT_TEAM="$TEAM_ID"
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$IDENTITY"
    # Per target: OAB_PROFILE_<target>; the Swift package targets get none.
    'PROVISIONING_PROFILE_SPECIFIER=$(OAB_PROFILE_$(TARGET_NAME))'
    OAB_PROFILE_OpenAdBlock="$APP_PROFILE"
    OAB_PROFILE_PacketTunnel="$TUNNEL_PROFILE"
    OTHER_CODE_SIGN_FLAGS="--timestamp${KEYCHAIN:+ --keychain $KEYCHAIN}"
)
[[ -n "${VERSION:-}" ]] && settings+=(MARKETING_VERSION="$VERSION")
[[ -n "${BUILD:-}" ]] && settings+=(CURRENT_PROJECT_VERSION="$BUILD")
# shellcheck disable=SC2206
[[ -n "${EXTRA_SETTINGS:-}" ]] && settings+=($EXTRA_SETTINGS)

rm -rf build/OpenAdBlock.xcarchive build/export
xcodebuild -scheme OpenAdBlock -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath build -archivePath build/OpenAdBlock.xcarchive "${settings[@]}" archive

cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>$EXPORT_METHOD</string>
    <key>signingStyle</key><string>manual</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingCertificate</key><string>$IDENTITY</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>$BUNDLE_PREFIX</key><string>$APP_PROFILE</string>
        <key>$BUNDLE_PREFIX.tunnel</key><string>$TUNNEL_PROFILE</string>
    </dict>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath build/OpenAdBlock.xcarchive -exportPath build/export \
    -exportOptionsPlist build/ExportOptions.plist

APP="build/export/Open AdBlock.app"
codesign --verify --deep --strict --verbose=2 "$APP"
lipo -info "$APP/Contents/MacOS/Open AdBlock"
for bundle in "$APP" "$APP/Contents/Library/SystemExtensions/$BUNDLE_PREFIX.tunnel.systemextension"; do
    echo "== $(basename "$bundle")"
    codesign -d --entitlements - --xml "$bundle" 2>/dev/null | plutil -p - | grep -A3 networkextension
done
