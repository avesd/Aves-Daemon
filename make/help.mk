.PHONY: help

help:
	@printf '%s\n' 'Development: build-macos run-macos build-worker' \
		'Checks: validate (shared Rust core)' \
		'Maintenance placeholders: $(MAINTENANCE_TARGETS)' \
		'Release placeholders: $(RELEASE_TARGETS)'
