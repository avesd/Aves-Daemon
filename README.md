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
