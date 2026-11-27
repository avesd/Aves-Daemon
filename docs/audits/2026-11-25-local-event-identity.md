# Avesd-Core-Monorepo maintainability audit, round two

## Summary

1 confirmed defect. Reviewed local event identity, persistence and the channel-specific settings, paths and lock contracts.

## Scope and method

Reviewed the current local worktree and compared the cited behavior with its owner contracts and earlier reports.

## Findings

### AUDIT-001 — Equivalent Unicode spellings at one event address can create two stored candidates

- **Class and rating** — Defect, P3, high confidence.
- **Evidence and contract** — The [local API](../../apps/macos/README.md#L54) defines one PUT resource per path ID and a distinct result for updating it. The [path comparison](../../apps/macos/Sources/AvesdOverlay/LocalServer/LocalMurmurServer.swift#L119) uses Swift string equality. The [storage key](../../apps/macos/Sources/AvesdOverlay/LocalServer/LocalEventStore.swift#L40), [existence check](../../apps/macos/Sources/AvesdOverlay/LocalServer/LocalEventStore.swift#L68) and [played-ID filter](../../apps/macos/Sources/AvesdOverlay/LocalServer/LocalEventStore.swift#L93) use SQLite's binary text comparison.
- **Behavior and impact** — For a single URL ending in the composed spelling of café, both composed and decomposed body IDs satisfied the path check. The actual store returned created for both writes, which the handler maps to 201. Excluding the second ID then returned the stale first payload.
- **Repair and verification** — Align the path comparison with the existing byte-exact storage and played-ID lookup. Check that a byte-identical repeat updates the existing candidate, a body with different bytes cannot create a second row at that address, and excluding the written ID removes it from selection.

## Verification record

Compared the route guard and status mapping with the real Swift store using synthetic Unicode IDs in a temporary SQLite database. Independently compiled the store and read a synthetic candidate in a new process before its deadline, then confirmed expiry. No HTTP listener, installed app, Keychain or user preferences were accessed.

## Suggested remediation order

1. `AUDIT-001` — Equivalent Unicode spellings at one event address can create two stored candidates.

## Follow-up checklist

- [ ] `AUDIT-001` — Align the path comparison with the existing byte-exact storage and played-ID lookup. Check that a byte-identical repeat updates the existing candidate, a body with different bytes cannot create a second row at that address, and excluding the written ID removes it from selection.
