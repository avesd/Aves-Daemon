#!/bin/bash
set -euo pipefail
: "${SPARKLE_PRIVATE_KEY:?}" "${VERSION:?}"

app="apps/macos/.build/distribution/Aves Daemon.app"
plist="$app/Contents/Info.plist"
test "$(plutil -extract CFBundleShortVersionString raw "$plist")" = "$VERSION"
lipo "$app/Contents/MacOS/AvesdOverlay" -verify_arch arm64
lipo "$app/Contents/Frameworks/libavesd_ffi.dylib" -verify_arch arm64
base="Aves-Daemon-$VERSION-macos-arm64"
archive="dist/$base.zip"
prefix="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/releases/download/v$VERSION/"
mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
awk -v heading="## $VERSION" '
    /^## / { show = ($0 == heading); next }
    /^# / || /^  Change intent: / { next }
    show { print }
' apps/macos/.changeset/history/*/CHANGELOG.md > dist/notes.md
test -s dist/notes.md
cp dist/notes.md "dist/$base.md"
tools=apps/macos/.build/artifacts/macos/Sparkle/bin
printf '%s' "$SPARKLE_PRIVATE_KEY" | "$tools/generate_appcast" --ed-key-file - \
    --download-url-prefix "$prefix" --embed-release-notes --maximum-deltas 0 dist
unset SPARKLE_PRIVATE_KEY

feed=dist/appcast.xml
test "$(xmllint --xpath 'string(/rss/channel/item/enclosure/@url)' "$feed")" = "$prefix$base.zip"
test "$(xmllint --xpath 'string(/rss/channel/item/*[local-name()="version"])' "$feed")" = "$(plutil -extract CFBundleVersion raw "$plist")"
signature=$(xmllint --xpath 'string(/rss/channel/item/enclosure/@*[local-name()="edSignature"])' "$feed")
public_key=$(plutil -extract SUPublicEDKey raw "$plist")
node --input-type=module - "$archive" "$signature" "$public_key" <<'JS'
import { createPublicKey, verify } from "node:crypto";
import { readFileSync } from "node:fs";
const [archive, signature, publicKey] = process.argv.slice(2);
const key = createPublicKey({ format: "jwk", key: {
    kty: "OKP", crv: "Ed25519", x: Buffer.from(publicKey, "base64").toString("base64url")
} });
if (!verify(null, readFileSync(archive), key, Buffer.from(signature, "base64"))) {
    throw new Error("Archive signature does not match the application's embedded public key");
}
JS
