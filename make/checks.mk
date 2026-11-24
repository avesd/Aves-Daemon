.PHONY: validate

DRAWING_ABI_TEST := cargo test --locked -p avesd-ffi --test drawing_abi

validate:
ifeq ($(shell uname -s),Darwin)
	$(DRAWING_ABI_TEST) --target-dir apps/macos/.build/rust
	$(MAKE) -C apps/macos rust brand CONFIGURATION=debug
	swift test --package-path apps/macos
else
	$(DRAWING_ABI_TEST)
endif
