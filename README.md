# Aves Daemon

A quiet, playful desktop tool. The macOS prototype shows aircraft flyovers, rain showers, sunrises, bridge lifts, turning tides, and last trains at the screen edge and keeps keyboard focus in the active app.

On macOS, scripts can also prepare events or display a personal note through the optional [local Murmur server](apps/macos/README.md#local-server).

Read the [design principles](docs/design.md) when designing or reviewing a screen-edge event.

## Source layout

| Path | Purpose |
| --- | --- |
| [apps/macos](apps/macos/) | Native macOS client |
| [apps/windows](apps/windows/) | Native Windows client |
| [apps/linux](apps/linux/) | Native Linux client |
| [crates/avesd-events](crates/avesd-events/) | Event models used by the desktop overlays |
| [crates/avesd-core](crates/avesd-core/) | Rust library for product logic shared across platforms |
| [crates/avesd-ffi](crates/avesd-ffi/) | Native C ABI for calling the Rust core from Swift |

Future iOS and Android clients belong in `apps/ios/` and `apps/android/` when development begins.
Native clients own their windows and input. The Rust core handles playback and drawing.

## Event data and playback

The macOS display preview uses the flyover from the six [sample events](crates/avesd-events/fixtures/).

The [overlay core](crates/avesd-core/src/overlay/) creates summary content and a seeded playback instance from one event. Each [effect](crates/avesd-core/src/overlay/effects/) emits ordered vector commands for the icon and the surrounding scenery. The playback clock controls field visibility, hover expansion, dismissal, and Reduce Motion.

The native renderer reads each frame through the [C header](crates/avesd-ffi/include/avesd.h).

## Development

Use the Node version in `.nvmrc` and the pnpm version in `package.json`. Run
`pnpm install --frozen-lockfile` at the repository root. Run `make validate`
to test maintenance updates and check that Rust and the C header agree on drawing commands
and colors. On macOS it also tests multi-source polling, authenticated playback, and usage
analytics against local servers.

Run `make run-macos` to build and restart Aves Daemon Local. Use `make build-macos-test`
for a separate, optimized test app. All three [macOS build channels](apps/macos/README.md#build-channels)
can run side by side. Run `make` to list the available targets.

## Maintenance

Run `make update-preview` to see candidate Swift package versions, GitHub Action commit SHAs,
the Rust compiler, and the CI Xcode version. It reads upstream metadata and leaves the worktree intact.

Run `make update-all` on macOS with the project Node and pnpm versions, installed Node
dependencies, rustup, and Xcode with Swift 6.2 or newer. It runs these targets in order.

| Target | Effect |
| --- | --- |
| `update-toolchains` | Check the selected local Swift toolchain, install the current stable Rust compiler and rustfmt with rustup, and record it in `rust-toolchain.toml`. Refresh `.xcode-version` from the default Xcode for the macOS runner named in the release workflow. |
| `update-dependencies` | Resolve the latest stable PostHog and Sparkle releases, including Sparkle's published ZIP checksum. Update `Package.swift` and `Package.resolved` after SwiftPM succeeds. Run `cargo update` within the workspace's manifest constraints and `pnpm update --latest` for Node dependencies. |
| `update-actions` | Resolve workflow actions pinned to versions or commit SHAs to their latest stable releases. Write full commit SHAs and refresh existing version comments. Set `GH_TOKEN` if you need authenticated GitHub API rate limits. |
| `validate`, `build-macos-release` | Run the maintenance, ABI, and native tests, then build the Release app with its updater. |

Rustup selects the pinned compiler in this repository. The workspace's `rust-version` declares
its minimum supported Rust version. On macOS the local build uses the installed Xcode selected
by `DEVELOPER_DIR` or `xcode-select`. The release runner selects the Xcode in `.xcode-version`.
To choose a different Xcode for one local command, prefix it with
`DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer`.

The shared `make organize update-all iud` sequence also formats the Rust workspace first
and finishes with a pnpm install, in-range update, and deduplication. Each target stops at
the first error. Earlier successful steps remain available for review and retry.

## Credits

Rain summaries use [MET Norway](https://www.met.no/en) forecasts under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
Aircraft data comes from [adsb.lol](https://www.adsb.lol/) under [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/).

## macOS client releases

The client owns [apps/macos/version.json](apps/macos/version.json). From the
root, use `make changeset TARGET=apps/macos BUMP=minor SUMMARY="Describe the client change."`
or choose the client in the interactive `make changeset` prompt.
Preview with `make version-dry-run TARGET=apps/macos` and apply with
`make version-packages TARGET=apps/macos`. The client keeps its quarterly
changelog and ledger under `apps/macos/.changeset/history/`. Each applied release increments the manifest's integer `build` once.
Each channel embeds `version` as `CFBundleShortVersionString` and `build`
as `CFBundleVersion`. Rebuilding the same manifest reuses both values.
Prepare a new changeset release for each distinct distributed update.

Run `make build-macos-release` to build the Swift executable and Rust library
in release mode for the current Mac's architecture. The local release bundle
is `apps/macos/.build/distribution/Aves Daemon.app`. Developer ID signing
and notarization are separate distribution steps.

To enable Sparkle in this bundle, set both `UPDATE_FEED_URL` (the stable HTTPS
appcast URL) and `UPDATE_PUBLIC_KEY` (the base64 Ed25519 public key from
Sparkle's `generate_keys`) when running `make build-macos-release`.
Omit both to build the Release app with updating disabled. Local and Test builds exclude Sparkle.
Keep the signing private
key with the publisher and supply the same public configuration on subsequent
releases. Apply the configured signing mode, archive the app preserving framework
symlinks, then use Sparkle's `generate_appcast` with the matching private key.
Upload the archive before the feed. See the [client update experience](apps/macos/README.md#software-updates).

For the Apple Silicon GitHub release, follow the [one-time signing setup and publishing instructions](docs/macos-release.md).
