#!/bin/bash
set -euo pipefail
app="apps/macos/$(make -s -C apps/macos app-path CHANNEL=release)"
case "${MACOS_SIGNING_MODE:-developer-id}" in
    ad-hoc)
        codesign --force --sign - "$app"
        codesign --verify --deep --strict "$app"
        exit 0
        ;;
    developer-id) ;;
    *)
        echo "Expected MACOS_SIGNING_MODE to be developer-id or ad-hoc." >&2
        exit 1
        ;;
esac
: "${DEVELOPER_ID_P12_BASE64:?}" "${DEVELOPER_ID_P12_PASSWORD:?}" "${APPLE_ID:?}" "${APPLE_TEAM_ID:?}" "${APPLE_APP_PASSWORD:?}"

umask 077
work=$(mktemp -d "$RUNNER_TEMP/avesd-sign.XXXXXX")
keychain="$work/signing.keychain-db"
cleanup() {
    security delete-keychain "$keychain" >/dev/null 2>&1 || true
    rm -rf "$work"
}
trap cleanup EXIT
password=$(openssl rand -hex 32)
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
printf '%s' "$DEVELOPER_ID_P12_BASE64" | base64 -D > "$work/developer.p12"
security import "$work/developer.p12" -k "$keychain" -P "$DEVELOPER_ID_P12_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" >/dev/null
identity=$(security find-identity -v -p codesigning "$keychain" |
    awk -v team="($APPLE_TEAM_ID)\"" '/"Developer ID Application:/ && $NF == team {print $2}')
if [[ ! "$identity" =~ ^[[:xdigit:]]{40}$ ]]; then
    echo "Expected one Developer ID Application identity for the configured team." >&2
    exit 1
fi

framework="$app/Contents/Frameworks/Sparkle.framework"
helpers="$framework/Versions/B"
sign=(codesign --force --options runtime --timestamp --keychain "$keychain" --sign "$identity")
"${sign[@]}" "$helpers/XPCServices/Installer.xpc"
"${sign[@]}" --preserve-metadata=entitlements "$helpers/XPCServices/Downloader.xpc"
"${sign[@]}" "$helpers/Autoupdate"
"${sign[@]}" "$helpers/Updater.app"
"${sign[@]}" "$framework"
"${sign[@]}" "$app/Contents/Frameworks/libavesd_ffi.dylib"
"${sign[@]}" "$app"
codesign --verify --deep --strict "$app"

ditto -c -k --keepParent "$app" "$work/submission.zip"
xcrun notarytool submit "$work/submission.zip" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" --wait --output-format json > "$work/notary.json"
jq '{id,status,message}' "$work/notary.json"
jq -e '.status == "Accepted"' "$work/notary.json" >/dev/null
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute "$app"
