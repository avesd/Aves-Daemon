.PHONY: run build rust brand

CONFIGURATION ?= debug
ifeq ($(CONFIGURATION),release)
APP := .build/distribution/Aves Daemon.app
CARGO_FLAGS := --release
else
APP := .build/Aves Daemon.app
endif

run: build
	open "$(APP)"

build: rust brand
	swift build -c $(CONFIGURATION) --product AvesdOverlay
	mkdir -p "$(APP)/Contents/Frameworks"
	rsync -a --delete .build/$(CONFIGURATION)/Sparkle.framework/ "$(APP)/Contents/Frameworks/Sparkle.framework/"
	install -C -S -m 755 .build/rust/$(CONFIGURATION)/libavesd_ffi.dylib "$(APP)/Contents/Frameworks/libavesd_ffi.dylib"
	mkdir -p "$(APP)/Contents/MacOS"
	install -C -S -m 755 .build/$(CONFIGURATION)/AvesdOverlay "$(APP)/Contents/MacOS/AvesdOverlay"
	mkdir -p "$(APP)/Contents/Resources/Fonts"
	rsync -rt --delete Sources/AvesdOverlay/Fonts/ "$(APP)/Contents/Resources/Fonts/"
	node configure-bundle.ts "$(APP)/Contents/Info.plist"

rust:
	cargo rustc $(CARGO_FLAGS) --locked --manifest-path ../../crates/avesd-ffi/Cargo.toml --target-dir .build/rust -- -C rpath=yes

brand:
	node generate-brand.ts
