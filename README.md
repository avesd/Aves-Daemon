# Aves Daemon

A quiet, playful desktop tool. The macOS prototype previews aircraft flyovers, rain showers, sunrises, bridge lifts, turning tides, and last trains at the screen edge and keeps keyboard focus in the active app.

Read the [design principles](docs/design.md) when designing or reviewing a screen-edge event.

## Source layout

| Path | Purpose |
| --- | --- |
| [apps/macos](apps/macos/) | Native macOS client |
| [apps/windows](apps/windows/) | Native Windows client |
| [apps/linux](apps/linux/) | Native Linux client |
| [crates/avesd-events](crates/avesd-events/) | Shared Rust event and aircraft snapshot wire types |
| [crates/avesd-core](crates/avesd-core/) | Rust library for product logic shared across platforms |
| [crates/avesd-ffi](crates/avesd-ffi/) | Native C ABI for calling the Rust core from Swift |
| [server/worker](server/worker/) | Cloudflare Worker, HTTP entry point, and Wrangler configuration |

Future iOS and Android clients belong in `apps/ios/` and `apps/android/` when development begins.
The clients own native windows and input. The Worker owns Cloudflare bindings. Shared rules belong in `avesd-core`, which builds for native and WebAssembly targets.

## Event data and playback

The [event contract](crates/avesd-events/src/lib.rs) describes an occurrence with a stable `id`, RFC 3339 `occurred_at`, snake-case `kind`, and typed `data`. The six [example records](crates/avesd-events/fixtures/) also power the desktop previews. Place-based observations carry an IANA time zone. Clients can read records independently and skip unsupported kinds. Additive fields can be ignored by older readers. Aircraft positions use the separate [regional snapshot contract](crates/avesd-events/src/aircraft.rs). A flyover ID identifies an occurrence and its aircraft ID identifies the vehicle.

The [overlay core](crates/avesd-core/src/overlay/) creates summary content and a seeded playback instance from one event. Each [effect](crates/avesd-core/src/overlay/effects/) emits ordered vector commands for the icon and the surrounding scenery. The playback clock controls field visibility, hover expansion, dismissal, and Reduce Motion. The Worker uses the event crate and the region module with the desktop overlay feature disabled.

Native clients pass one JSON record to `avesd_overlay_create`, or choose a bundled sample with `avesd_overlay_preview`. They read display content once and advance the session with monotonic elapsed milliseconds and the native hover hit test. A frame carries the panel state and two borrowed command buffers. Deferred renderers copy both layers on creation. After each call to `avesd_overlay_advance_changes`, they refresh only the owned layer snapshots marked as changed. The [C header](crates/avesd-ffi/include/avesd.h) defines coordinates, drawing operations, and ownership. Test wire compatibility, playback, [keyframes](crates/avesd-core/tests/fixtures/overlay/), and Worker snapshots with `cargo test --locked --workspace`.

## Development

Run `make` at the root to list the targets defined in `make/`. Build the
[macOS overlay prototype](apps/macos/README.md) with `make build-macos` or launch
it with `make run-macos`.

Run `make validate` to check the shared Rust core. To build the Worker for WebAssembly, install the target and build its workspace package:

```sh
rustup target add wasm32-unknown-unknown
make build-worker
```

For a local HTTP preview, install the build tool once, then run Wrangler from the Worker directory:

```sh
cargo install --locked --version '0.9.0' worker-build
cd server/worker
npx wrangler@4 dev --local
```

### Regional event polling

Call `GET /v1/regions/{region_id}/event` with one optional `played` query parameter
per event displayed in the past three hours (up to 64 IDs of 256 bytes each).
A 200 response contains one [event record](#event-data-and-playback) ready for
immediate playback. A 204 response means there is nothing to play. These
responses are private and never cached. A source has four seconds to answer.
Other available events remain eligible if a source fails. When no eligible
event remains and a source failed, the endpoint returns 503 and forwards an
available `Retry-After` from the aircraft or tide source.

The Worker groups events into **nearby** and **worldwide** pools. It removes
expired and played IDs, keeping a shared occurrence in the nearby pool once.
It then makes one quiet-response draw per poll. On a play, it picks a pool
by weight and samples uniformly within that pool. Either pool can supply the
response when the other is empty. Wrangler variables `EVENT_NEARBY_PERCENT`
and `EVENT_DROP_PERCENT` accept whole percentages from 0 to 100 and default
to 70 and 80 respectively. With continuously available events and the
client's 5/10/15-minute cadence, this averages about 31 minutes between plays.

| Event | Eligibility and identity |
| --- | --- |
| Flyover | Nearby aircraft in the current regional snapshot. The existing `RegionalFlyovers` Durable Object retains first and latest observation per aircraft. The region, aircraft address and first observation identify a pass. After a gap of over 20 minutes between aircraft positions the next observation starts a new pass. |
| Sunrise | Nearby and worldwide. The Worker calculates sunrises locally and keeps one UTC day's almanac per isolate for the principal locations in the [IANA time zone database](https://www.iana.org/time-zones). Each sunrise is eligible for 15 minutes. Both scopes use the same location and local-date ID. Cells without a named catalog point use their own center, labeled in UTC. The event requires a sunrise on both solar days for its comparison with yesterday. |
| Turning tide | Nearby tidal stations in the [NOAA CO-OPS network](https://tidesandcurrents.noaa.gov/web_services_info.html). The Worker selects the closest station in the regional search circle, then confirms a predicted high or low with five consecutive six-minute water levels: at least two centimeters of change on each side, with the last two readings moving away from the extremum. The Worker selects the fresh confirmed turn closest to the prediction within one hour. The event remains eligible for 15 minutes after confirmation and displays the observation time in UTC. The station and predicted extremum identify the occurrence across regions. |

The [source modules](server/worker/src/sources) own acquisition, credentials and
shared data caches. NOAA's station list and dated predictions are cached for a
day and station observations for five minutes. The [event providers](server/worker/src/events/mod.rs)
map supported scopes to occurrences with stable IDs and expiry. Register a new
provider there. The [service](server/worker/src/service.rs) owns playback history
filtering, quiet responses and scope selection.

### Regional aircraft snapshots

Call `GET /v1/regions/{region_id}/aircraft` with a canonical lowercase H3 cell ID
at resolution 6, for example `/v1/regions/86283082fffffff/aircraft`.
The search circle is centered on the cell and extends 3 km beyond its farthest
boundary vertex. Adjacent regions can contain the same aircraft.

```json
{
  "region_id": "86283082fffffff",
  "fetched_at": "2026-11-21T17:30:08Z",
  "aircraft": [
    {
      "aircraft_id": "icao24:a1b2c3",
      "latitude": 37.775,
      "longitude": -122.418,
      "position_at": "2026-11-21T17:30:05Z",
      "ground_track_deg": 278.0
    }
  ]
}
```

The Worker queries [adsb.lol](https://www.adsb.lol/docs/open-data/api) on
demand. Aircraft data is available under
[ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/).
Set the optional Worker secret `ADSB_LOL_API_KEY` to use an assigned quota.
Positions are at most 30 seconds old at fetch time. Known ground targets are
excluded. Track is clockwise from true north in degrees, or `null` when
unavailable. Non-ICAO addresses use the `adsblol:` prefix.

Successful snapshots, including empty results, are cached per region for 15
seconds in the serving Cloudflare data center. Cache hits preserve both UTC
timestamps. The endpoint requires no database. An invalid cell returns 400.
An unavailable upstream returns 503 and forwards its Retry-After header when
present. Run `cargo test -p avesd-core -p avesd-worker` for the geometry and
snapshot checks.

## macOS client releases

The client owns [apps/macos/version.json](apps/macos/version.json). From the
root, use `make changeset TARGET=apps/macos BUMP=minor SUMMARY="Describe the client change."`
or choose the client in the interactive `make changeset` prompt.
Preview with `make version-dry-run TARGET=apps/macos` and apply with
`make version-packages TARGET=apps/macos`. The client keeps its quarterly
changelog and ledger under `apps/macos/.changeset/history/`. The next
`make build-macos` embeds the manifest version into the application.

## Worker releases

The production version lives in [server/worker/version.json](server/worker/version.json).
Rust crate versions track the build packages independently. Use the Node version
in `.nvmrc` and the pnpm version in `package.json`, then run
`pnpm install --frozen-lockfile` at the repository root.

1. Record a change with `make changeset`. For non-interactive use, run
   `make changeset TARGET=server/worker BUMP=patch SUMMARY="Describe the change."`.
2. Run `make version-dry-run` to preview the next version. The largest requested
   bump wins. The version rules skip repeated-digit and consecutive-digit versions.
3. Run `make version-packages` to apply the release locally. Review the version
   manifest, consumed notes from `.changeset/`, and the Worker’s
   `.changeset/history/YYYY-QN/{CHANGELOG.md,ledger.yaml}` together.

`make help` lists the release commands and reserved maintenance targets.
