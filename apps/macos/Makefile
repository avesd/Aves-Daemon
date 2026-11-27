.PHONY: run build test rust brand app-path sparkle-tools-path
.DEFAULT_GOAL := run

CHANNEL ?= local
CHANNELS := Sources/AvesdEnvironment/channels.json
channel_key := $(subst ','"'"',$(CHANNEL))
channel_field = $(shell plutil -extract '$(channel_key).$(1)' raw -o - "$(CHANNELS)")
ifeq ($(shell plutil -extract '$(channel_key)' json -expect dictionary -o /dev/null "$(CHANNELS)" >/dev/null 2>&1 && echo found),)
$(error Unknown macOS channel '$(CHANNEL)')
endif

APP := $(call channel_field,appDirectory)/$(call channel_field,appName).app
SWIFT_BUILD := $(call channel_field,scratchPath)
CONFIGURATION ?= $(call channel_field,configuration)
export AVESD_BUILD_CHANNEL := $(CHANNEL)
CARGO_FLAGS := $(if $(filter release,$(CONFIGURATION)),--release)

app-path:
	@printf '%s\n' "$(APP)"

sparkle-tools-path:
	@printf '%s\n' "$(SWIFT_BUILD)/artifacts/macos/Sparkle/bin"

run: build
ifeq ($(call channel_field,restartsOnRun),true)
	open -n "$(APP)" --args --restart-local
else
	open "$(APP)"
endif

build: rust brand
	xcrun swift build --manifest-cache none --scratch-path "$(SWIFT_BUILD)" -c $(CONFIGURATION) --product AvesdOverlay
	mkdir -p "$(APP)/Contents/Frameworks"
ifeq ($(call channel_field,includesUpdater),true)
	rsync -a --delete "$(SWIFT_BUILD)/$(CONFIGURATION)/Sparkle.framework/" "$(APP)/Contents/Frameworks/Sparkle.framework/"
else
	$(RM) -r "$(APP)/Contents/Frameworks/Sparkle.framework"
endif
	install -C -S -m 755 .build/rust/$(CONFIGURATION)/libavesd_ffi.dylib "$(APP)/Contents/Frameworks/libavesd_ffi.dylib"
	mkdir -p "$(APP)/Contents/MacOS"
	install -C -S -m 755 "$(SWIFT_BUILD)/$(CONFIGURATION)/AvesdOverlay" "$(APP)/Contents/MacOS/AvesdOverlay"
	mkdir -p "$(APP)/Contents/Resources/Fonts"
	rsync -a "$(SWIFT_BUILD)/$(CONFIGURATION)"/PostHog_*.bundle "$(APP)/Contents/Resources/"
	rsync -rt --delete Sources/AvesdOverlay/Fonts/ "$(APP)/Contents/Resources/Fonts/"
	rsync -rct --delay-updates --delete-after --include='/*.lproj/' \
	    $(foreach table,Settings Overlay InfoPlist,--include='/*.lproj/$(table).strings' --include='/*.lproj/$(table).stringsdict') \
	    --exclude='*' "$(SWIFT_BUILD)/$(CONFIGURATION)/AvesdOverlay_AvesdEnvironment.bundle/" "$(APP)/Contents/Resources/"
	node configure-bundle.ts "$(CHANNEL)" "$(APP)/Contents/Info.plist"

test: rust brand
	xcrun swift test --manifest-cache none --scratch-path "$(SWIFT_BUILD)" -c $(CONFIGURATION)

rust:
	cargo rustc $(CARGO_FLAGS) --locked --manifest-path ../../crates/avesd-ffi/Cargo.toml --target-dir .build/rust -- -C rpath=yes

brand:
	node generate-brand.ts
