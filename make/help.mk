.PHONY: help

help:
	@printf '%s\n' 'Development: build-macos run-macos build-macos-test' \
		'Checks: validate (maintenance pins, drawing ABI, and native tests on macOS)' \
		'Maintenance: $(MAINTENANCE_TARGETS)' \
		'Maintenance placeholders: $(MAINTENANCE_PLACEHOLDERS)' \
		'macOS releases: $(RELEASE_TARGETS) build-macos-release'
