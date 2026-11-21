# Avesd

## Source layout

| Path | Purpose |
| --- | --- |
| [apps/macos](apps/macos/) | Native macOS client |
| [apps/windows](apps/windows/) | Native Windows client |
| [apps/linux](apps/linux/) | Native Linux client |
| [crates/avesd-core](crates/avesd-core/) | Rust library for product logic shared across platforms |
| [crates/avesd-ffi](crates/avesd-ffi/) | Native C ABI for calling the Rust core from Swift |
| [server/worker](server/worker/) | Cloudflare Worker, HTTP entry point, and Wrangler configuration |

Future iOS and Android clients belong in `apps/ios/` and `apps/android/` when development begins.
The clients own native windows and input. The Worker owns Cloudflare bindings. Shared rules belong in `avesd-core`, which builds for native and WebAssembly targets.

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

The scaffold responds to requests with HTTP 404 until application routes are added.

## Maintenance and releases

`make help` lists the reserved maintenance and release targets, including
`organize`, `update-all`, `iud`, `version-dry-run`, and `version-packages`.
Each placeholder reports its name and exits with an error so callers can stop
when a requested operation is unavailable.
