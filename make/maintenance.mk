MAINTENANCE_TARGETS := organize depcheck update-all update-dependencies update-actions update-self iud ud cloc refresh-cloc sort sort-all sort-dependencies sort-workspace comment

.PHONY: $(MAINTENANCE_TARGETS)

$(MAINTENANCE_TARGETS):
	$(error $@ is a placeholder until the maintenance workflow is configured)
