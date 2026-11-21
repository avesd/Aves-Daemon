.PHONY: build-macos run-macos build-worker

build-macos:
	$(MAKE) -C apps/macos build

run-macos:
	$(MAKE) -C apps/macos run

build-worker:
	cargo build -p avesd-worker --target wasm32-unknown-unknown
