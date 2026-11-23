.PHONY: build-macos run-macos

build-macos:
	$(MAKE) -C apps/macos build

run-macos:
	$(MAKE) -C apps/macos run
