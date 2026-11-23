# Aves Daemon

A quiet, playful desktop tool. The macOS prototype previews aircraft flyovers, rain showers, sunrises, bridge lifts, turning tides, and last trains at the screen edge and keeps keyboard focus in the active app.

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

The six [sample events](crates/avesd-events/fixtures/) power the desktop previews.

The [overlay core](crates/avesd-core/src/overlay/) creates summary content and a seeded playback instance from one event. Each [effect](crates/avesd-core/src/overlay/effects/) emits ordered vector commands for the icon and the surrounding scenery. The playback clock controls field visibility, hover expansion, dismissal, and Reduce Motion.

The native renderer reads each frame through the [C header](crates/avesd-ffi/include/avesd.h).
The [keyframe fixtures](crates/avesd-core/tests/fixtures/overlay/) cover all six previews.

## Development

Use the Node version in `.nvmrc` and the pnpm version in `package.json`. Run
`pnpm install --frozen-lockfile` at the repository root. Run `make validate`
for the Rust workspace and the macOS release tests.

Run `make` to list the available targets. Build the [macOS overlay](apps/macos/README.md)
with `make build-macos` or launch it with `make run-macos`.

## Credits

Rain summaries use [MET Norway](https://www.met.no/en) forecasts under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
Aircraft data comes from [adsb.lol](https://www.adsb.lol/) under [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/).

## macOS client releases

The client owns [apps/macos/version.json](apps/macos/version.json). From the
root, use `make changeset TARGET=apps/macos BUMP=minor SUMMARY="Describe the client change."`
or choose the client in the interactive `make changeset` prompt.
Preview with `make version-dry-run TARGET=apps/macos` and apply with
`make version-packages TARGET=apps/macos`. The client keeps its quarterly
changelog and ledger under `apps/macos/.changeset/history/`. The next
`make build-macos` embeds the manifest version into the application.
