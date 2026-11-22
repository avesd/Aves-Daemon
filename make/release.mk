RELEASE_TARGETS := changeset version-dry-run version-packages
BUMP ?= patch

export AVESD_CHANGESET_TARGET = $(TARGET)
export AVESD_CHANGESET_BUMP := $(BUMP)
export AVESD_CHANGESET_SUMMARY := $(SUMMARY)

.PHONY: $(RELEASE_TARGETS)

version-dry-run version-packages: TARGET ?= server/worker
ifneq ($(strip $(SUMMARY)),)
changeset: TARGET ?= server/worker
endif

changeset:
	node scripts/release/release-changesets.ts add

version-dry-run:
	node scripts/release/release-changesets.ts plan

version-packages:
	node scripts/release/release-changesets.ts apply
