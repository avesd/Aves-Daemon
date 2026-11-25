.PHONY: validate

DRAWING_ABI_TEST := cargo test --locked -p avesd-ffi --test drawing_abi

validate:
ifeq ($(shell uname -s),Darwin)
	$(DRAWING_ABI_TEST) --target-dir apps/macos/.build/rust
	$(MAKE) -C apps/macos test CHANNEL=local CONFIGURATION=debug
else
	$(DRAWING_ABI_TEST)
endif
