.PHONY: validate

validate:
	cargo test --locked --workspace
	node --test scripts/release/test/macos-release.test.ts
