# macOS release setup

The [release workflow](../.github/workflows/release-macos.yml) publishes an Apple Silicon ZIP and Sparkle appcast to GitHub Releases. The version and build come from [the client manifest](../apps/macos/version.json).

## Configure the release environment

In the `avesd/Aves-Daemon` repository, open **Settings → Environments → New environment**, name it `macos-release`, and choose **Configure environment**. Under **Deployment branches and tags**, select **Selected branches and tags** and add a branch rule for `main`. Enable GitHub Actions for the repository. The publish job requests `contents: write` on its built-in `GITHUB_TOKEN` to create version tags and releases.

### Generate the Sparkle key once

On the release owner's Mac, run the following from the client repository root after the [development setup](../README.md#development). The dedicated Keychain account lets you repeat the command to retrieve the same public key.

```sh
make build-macos-release
keys=apps/macos/.build/artifacts/macos/Sparkle/bin/generate_keys
"$keys" --account ai.avesd.daemon
"$keys" --account ai.avesd.daemon -p
```

With GitHub CLI signed into an account with repository admin access, run the following from the same shell. The private key passes from a temporary, owner-only directory into the environment secret. Keep an encrypted recovery copy under your normal signing-key backup policy. See [Sparkle key management](https://sparkle-project.org/documentation/).

```sh
(
  set -eu
  umask 077
  export_dir=$(mktemp -d)
  trap 'rm -rf "$export_dir"' EXIT
  "$keys" --account ai.avesd.daemon -x "$export_dir/sparkle.key"
  gh secret set SPARKLE_PRIVATE_KEY -R avesd/Aves-Daemon --env macos-release < "$export_dir/sparkle.key"
)
gh variable set UPDATE_PUBLIC_KEY -R avesd/Aves-Daemon --env macos-release --body "$("$keys" --account ai.avesd.daemon -p)"
gh variable set UPDATE_FEED_URL -R avesd/Aves-Daemon --env macos-release --body 'https://github.com/avesd/Aves-Daemon/releases/latest/download/appcast.xml'
```

### Test releases before Apple Developer enrollment

Configure the Sparkle settings above and set one additional environment variable:

```sh
gh variable set MACOS_SIGNING_MODE -R avesd/Aves-Daemon --env macos-release --body ad-hoc
```

In this mode the runner applies an ad-hoc signature to the app bundle and signs
the final ZIP with Sparkle. These releases follow the same GitHub Latest and
appcast publication flow. Gatekeeper may block the first launch of a downloaded
copy because Apple has not verified the developer or notarized the app.

When you enroll, configure the Apple credentials below and change
`MACOS_SIGNING_MODE` to `developer-id` before the next version bump. Keep the
same Sparkle key pair so existing installations can verify the new ZIP.

### Configure Apple signing and notarization

In Keychain Access on the signing Mac, open **My Certificates**, select the **Developer ID Application** identity with its private key, and export it as a password-protected `.p12`. Use Apple's [Developer ID certificate instructions](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/) to obtain an identity if needed. Find your Team ID in your Apple Developer membership. Generate an [app-specific password](https://support.apple.com/en-us/102654) for notarization using the Apple account on that team.

Use **Environment variables** and **Environment secrets** inside `macos-release`. The following table lists the release settings. The Apple credentials are required only in Developer ID mode.

| Type | Name | Value |
| --- | --- | --- |
| Variable | `UPDATE_PUBLIC_KEY` | Base64 public key printed by Sparkle |
| Variable | `UPDATE_FEED_URL` | Stable latest-release appcast URL shown above |
| Variable | `MACOS_SIGNING_MODE` | `developer-id` (default) or `ad-hoc` for pre-enrollment testing |
| Variable | `APPLE_TEAM_ID` | Apple Developer Team ID for the certificate and notarization account |
| Secret | `SPARKLE_PRIVATE_KEY` | Contents of the Sparkle private key export |
| Secret | `DEVELOPER_ID_P12_BASE64` | Base64 of the complete exported PKCS#12 file |
| Secret | `DEVELOPER_ID_P12_PASSWORD` | Password used to export that file |
| Secret | `APPLE_ID` | Apple account email for notarization |
| Secret | `APPLE_APP_PASSWORD` | App-specific password for that account |

On macOS you can upload the PKCS#12 directly, using your export's path. For the three remaining secrets, `gh secret set` will prompt for the value.

```sh
base64 -i "/path/to/Developer-ID-Application.p12" | gh secret set DEVELOPER_ID_P12_BASE64 -R avesd/Aves-Daemon --env macos-release
gh secret set DEVELOPER_ID_P12_PASSWORD -R avesd/Aves-Daemon --env macos-release
gh secret set APPLE_ID -R avesd/Aves-Daemon --env macos-release
gh secret set APPLE_APP_PASSWORD -R avesd/Aves-Daemon --env macos-release
gh variable set APPLE_TEAM_ID -R avesd/Aves-Daemon --env macos-release --body 'YOUR_TEAM_ID'
```

## Publish a version

1. Preview with `make version-dry-run`, then run `make version-packages` and merge the manifest and generated quarterly history into `main`.
2. Open **Actions → Release macOS**. The workflow validates the version transition, builds the app and applies the configured signing mode. In Developer ID mode it also waits for Apple to accept the notarization and staples the ticket. It verifies the final ZIP signature against the public key embedded in the app.
3. The publish job attaches the ZIP and `appcast.xml` to a draft for `v<version>` targeting the triggering SHA, then publishes it. The current release on `main` becomes Latest. To retry a failed release, use **Re-run failed jobs** on the original run.
4. For the first rollout, download the ZIP from Releases, extract the app into Applications, and choose **Check for Updates…**. On the following release, verify that the previously installed copy offers the new version and relaunches with its settings preserved.
