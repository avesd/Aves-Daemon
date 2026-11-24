.PHONY: help

help:
	@printf '%s\n' 'Development: build-macos run-macos' \
		'Checks: validate (drawing ABI, plus native playback tests on macOS)' \
		'Maintenance placeholders: $(MAINTENANCE_TARGETS)' \
		'macOS releases: $(RELEASE_TARGETS) build-macos-release'
