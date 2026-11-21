# Share one sandbox document per canvas

Date: 2026-11-20
Status: Accepted

## Context

A canvas can replace one Agent-authored block while other blocks retain their
visible content, input state, and animations. The desktop must continue to
authorize each block version independently. See the current [block isolation
contract](../dashboard-blocks.md#isolation-and-observation).

## Decision

Use one unprivileged iframe, protocol document, and message channel per canvas.
Insert each block in a separate scoped root. Keep native authorization in
per-block-version leases tied to the trusted window and canvas. Lease and
deduplicated request state share the lifetime of that owner. Recheck a lease
when an action resumes after an asynchronous read.

## Alternatives considered

- Use a separate iframe and channel for each block. This gives blocks separate
  browser execution contexts at the cost of managing a document per block.
- Replace the whole canvas document when a block changes. This simplifies
  replacement but discards DOM and interaction state in sibling blocks.

## Consequences

Blocks share a JavaScript execution boundary. Their scoped roots separate
styles and lifecycles, while native capabilities remain protected by the
host's lease checks. Replacing one root preserves the existing canvas document
and other mounts.
