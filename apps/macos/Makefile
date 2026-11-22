.PHONY: run build rust brand

APP := .build/Aves Daemon.app

run: build
	open "$(APP)"

build: rust brand
	swift build --product AvesdOverlay
	mkdir -p "$(APP)/Contents/Frameworks"
	install -C -S -m 755 .build/rust/debug/libavesd_ffi.dylib "$(APP)/Contents/Frameworks/libavesd_ffi.dylib"
	mkdir -p "$(APP)/Contents/MacOS"
	install -C -S -m 755 .build/debug/AvesdOverlay "$(APP)/Contents/MacOS/AvesdOverlay"
	mkdir -p "$(APP)/Contents/Resources/Fonts"
	rsync -rt --delete Sources/AvesdOverlay/Fonts/ "$(APP)/Contents/Resources/Fonts/"
	version=$$(plutil -extract version raw -expect string version.json) && \
		plutil -replace CFBundleShortVersionString -string "$$version" -o .build/Info.plist Info.plist
	install -C -S -m 644 .build/Info.plist "$(APP)/Contents/Info.plist"

rust:
	cargo rustc --locked --manifest-path ../../crates/avesd-ffi/Cargo.toml --target-dir .build/rust -- -C rpath=yes

brand:
	node generate-brand.ts
