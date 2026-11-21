.PHONY: run build rust

run: rust
	swift run AvesdOverlay

build: rust
	swift build --product AvesdOverlay

rust:
	cargo rustc --locked --manifest-path ../../crates/avesd-ffi/Cargo.toml --target-dir .build/rust -- -C rpath=yes
