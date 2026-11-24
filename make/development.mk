.PHONY: build-macos build-macos-release run-macos

build-macos:
	$(MAKE) -C apps/macos build

build-macos-release:
	$(MAKE) -C apps/macos build CONFIGURATION=release

run-macos:
	$(MAKE) -C apps/macos run
