.PHONY: help

help:
	@printf '%s\n' 'Development: build-macos run-macos' \
		'Checks: validate (Rust workspace and macOS release tests)' \
		'Maintenance placeholders: $(MAINTENANCE_TARGETS)' \
		'macOS releases: $(RELEASE_TARGETS) build-macos-release'
