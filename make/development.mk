.PHONY: build-macos build-macos-test build-macos-release run-macos

build-macos:
	$(MAKE) -C apps/macos build

build-macos-test:
	$(MAKE) -C apps/macos build CHANNEL=test

build-macos-release:
	$(MAKE) -C apps/macos build CHANNEL=release

run-macos:
	$(MAKE) -C apps/macos run
