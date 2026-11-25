MAINTENANCE_TARGETS := organize update-preview update-all update-toolchains update-dependencies update-actions iud
MAINTENANCE_PLACEHOLDERS := depcheck update-self ud cloc refresh-cloc sort sort-all sort-dependencies sort-workspace comment

.PHONY: $(MAINTENANCE_TARGETS) $(MAINTENANCE_PLACEHOLDERS)

ifneq ($(filter $(MAINTENANCE_TARGETS),$(MAKECMDGOALS)),)
.NOTPARALLEL:
endif

organize:
	cargo fmt --all

update-preview:
	node scripts/maintenance/update.ts preview

update-all:
	$(MAKE) update-toolchains
	$(MAKE) update-dependencies
	$(MAKE) update-actions
	$(MAKE) validate
	$(MAKE) build-macos-release

update-toolchains:
	node scripts/maintenance/update.ts toolchains

update-dependencies:
	node scripts/maintenance/update.ts swift
	cargo update
	pnpm update --latest

update-actions:
	node scripts/maintenance/update.ts actions

iud:
	pnpm install --no-frozen-lockfile
	pnpm update
	pnpm dedupe

$(MAINTENANCE_PLACEHOLDERS):
	$(error $@ is a placeholder until the maintenance workflow is configured)
