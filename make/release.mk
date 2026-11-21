RELEASE_TARGETS := changeset version-dry-run version-packages

.PHONY: $(RELEASE_TARGETS)

$(RELEASE_TARGETS):
	$(error $@ is a placeholder until the release workflow is configured)
