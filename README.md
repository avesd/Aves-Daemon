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

Run the [macOS overlay prototype](apps/macos/README.md) with `make -C apps/macos run`.

Run `cargo check` from the repository root to check the shared core. To build the Worker for WebAssembly, install the target and build its workspace package:

```sh
rustup target add wasm32-unknown-unknown
cargo build -p avesd-worker --target wasm32-unknown-unknown
```

For a local HTTP preview, install the build tool once, then run Wrangler from the Worker directory:

```sh
cargo install --locked --version '0.9.0' worker-build
cd server/worker
npx wrangler@4 dev --local
```

The scaffold responds to requests with HTTP 404 until application routes are added.
