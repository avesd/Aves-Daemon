# Repository Audit - 2026-11-24

## Summary

The joint Aves Daemon and Aves Daemon Service audit found three client defects. The macOS playback-history limit defect is resolved. Two presentation defects affecting rain and sunrise events remain open.

## Scope and Method

Reviewed the macOS source configuration, history, regional requests, Rust event types, native playback entry point and overlay content against the Murmur route and event providers. The inspected worktrees were Avesd Core Monorepo at `c0e2b55` and Aves Daemon Service at `a7dbe36`. The checks below used synthetic data and local code. Production traffic, visual inspection of the macOS window and other platforms were outside this review.

## Findings

### AUDIT-001 - A busy source can exceed the playback-history limit

- **Class and severity** Defect, P2, high confidence.
- **Evidence** The macOS settings allow a fixed one-minute interval. The poller retains three hours of history, sorts every known ID for the destination by key, and appends all of them to the request. Murmur rejects a request containing more than 64 IDs before it polls any provider. [Interval policy](../../apps/macos/Sources/AvesdOverlay/DaemonPreferences.swift#L30) · [Request construction](../../apps/macos/Sources/AvesdOverlay/EventPolling.swift#L61) · [Murmur public contract](https://github.com/avesd/Aves-Daemon-Service/blob/a7dbe36c392f4615ebcaaa6063705c30e19cc152/docs/architecture/event-api.md#L3) · [Route guard](https://github.com/avesd/Aves-Daemon-Service/blob/a7dbe36c392f4615ebcaaa6063705c30e19cc152/apis/murmur/src/routes/public.ts#L47)
- **Decision boundary** Local deduplication spans three hours across launches. The wire contract allows up to 64 IDs of at most 256 UTF-8 bytes each. [Client history contract](../../apps/macos/README.md#L43)
- **Behavior and impact** A user running a one-minute fixed schedule against a busy source can play 65 distinct events within the retention window. Subsequent polls to that source return HTTP 400 until enough history expires. The stored history survives an app restart. The default five-minute schedule cannot reach 65 plays in three hours during ordinary continuous polling. [History persistence](../../apps/macos/Sources/AvesdOverlay/EventPolling.swift#L105)
- **Remediation and verification** Keep the full local history. When serializing a request, choose the most recently played IDs that fit the wire limits and count any existing `played` parameters on fixed URLs toward the same budget. Verify that 64 and 65 eligible local records both produce valid requests, that other fixed-URL parameters survive and that an older ID omitted from the request still prevents a local replay.
- **Status** Resolved. Fixed-source parameters and playback history share the same request budget. The native regression covers a preset ID plus a full history, over-limit presets and UTF-8 lengths, preserved query encoding, and suppression of an older ID omitted from the request. [Query construction](../../apps/macos/Sources/AvesdOverlay/EventPolling.swift#L14) · [Native regression](../../apps/macos/Tests/AvesdOverlayTests/PollingTests.swift#L295)

### AUDIT-002 - A rain event with one intensity field cannot play

- **Class and severity** Defect, P3, high confidence.
- **Evidence** The wire contract and Rust model make the two intensity fields independently optional. The overlay selects its generic summary only when both fields are absent. In the comparison branch, extracting either missing field returns an empty playback handle. [Wire fields](https://github.com/avesd/Aves-Daemon-Service/blob/a7dbe36c392f4615ebcaaa6063705c30e19cc152/packages-shared/event-contract/src/index.ts#L8) · [Rust rain model](../../crates/avesd-events/src/rain.rs#L13) · [Summary construction](../../crates/avesd-core/src/overlay/content.rs#L86) · [Native entry point](../../crates/avesd-ffi/src/overlay.rs#L30)
- **Decision boundary and impact** The app supports custom event URLs. A source reporting only the current intensity can supply a valid event that the native client repeatedly receives and skips. It never enters playback history. The official Murmur rain provider currently omits both intensity fields and plays successfully. [Custom feeds](../../apps/macos/README.md#L39) · [Playback acceptance](../../apps/macos/Sources/AvesdOverlay/EventPolling.swift#L96) · [Official rain payload](https://github.com/avesd/Aves-Daemon-Service/blob/a7dbe36c392f4615ebcaaa6063705c30e19cc152/apis/murmur/src/events/rain/index.ts#L36)
- **Remediation and verification** Compare intensities only when both measurements exist. With a single measurement, use wording that expresses the available observation without inferring a trend. Exercise all four presence combinations through the native entry point, including an explicit intensity of `none`.

### AUDIT-003 - The sunrise detail claims an exact match after a sub-minute change

- **Class and severity** Defect, P3, high confidence.
- **Evidence** Murmur computes the change in civil time and truncates it to whole minutes. The overlay interprets zero as “Sunrise at the same time as yesterday” in both the detail and accessibility text. [Provider calculation](https://github.com/avesd/Aves-Daemon-Service/blob/a7dbe36c392f4615ebcaaa6063705c30e19cc152/apis/murmur/src/events/sunrise/index.ts#L61) · [Client interpretation](../../crates/avesd-core/src/overlay/content.rs#L113) · [Clock and accessibility text](../../crates/avesd-core/src/overlay/content.rs#L155)
- **Decision boundary and impact** The public event describes a civil-day comparison. A zero difference in whole minutes allows a change of up to 59 seconds in either direction. For Tokyo on November 22–24, 2026, the generated local sunrise times were 06:23:18, 06:24:17 and 06:25:16. The panel clock advanced a minute each day, and both later events described the time as identical. Playback and the reported instant remained correct. [Sunrise contract](https://github.com/avesd/Aves-Daemon-Service/blob/a7dbe36c392f4615ebcaaa6063705c30e19cc152/docs/architecture/event-api.md#L11)
- **Remediation and verification** Use wording such as “Within a minute of yesterday’s sunrise” for zero. Verify the detail and accessibility text for a 59-second change across a displayed minute, identical times and a nonzero whole-minute change.

## Hardening Opportunities

### HARDENING-001 - Identify the bridge in expanded NDW events

Murmur supplies the Dutch bridge location code and the country as separate fields. For the fixture code `NL1`, playback showed the Netherlands, local time and river traffic, leaving the code out of the detail and accessibility text. The current design leaves the choice of detail to each event. If distinguishing individual Dutch bridges is a product goal, add the supplied identifier to the expanded card and accessibility description when the place does not identify the bridge. Verify that two bridges opening in the same minute are distinguishable. [NDW mapping](https://github.com/avesd/Aves-Daemon-Service/blob/a7dbe36c392f4615ebcaaa6063705c30e19cc152/apis/murmur/src/events/bridge-lift/index.ts#L67) · [Bridge detail](../../crates/avesd-core/src/overlay/content.rs#L127) · [Design principles](../design.md)

## Verification Record

- Compiled the current Swift poller and preferences with an in-memory history store. After 64 and 65 distinct playback callbacks, passed the generated URLs to the current Murmur public handler with all providers disabled. It returned 204 for 64 and 400 for 65.
- Exercised the native entry point with neither rain intensity, only the previous value, only the current value and both values. Both single-field cases returned an empty handle. The two other cases produced summaries. The existing FFI test exercises the fieldless and paired cases. [FFI coverage](../../crates/avesd-ffi/src/overlay.rs#L137)
- Passed locally generated flyover, rain, sunrise, bridge and turning-tide payloads through the client FFI. All five kinds opened a playback session. The six shared fixtures, including the last-train preview, matched byte for byte and all opened sessions. All 418 catalog time zones were accepted. Checked the Tokyo sunrise detail and accessibility output across consecutive civil days.
- The targeted checks used local sources and synthetic upstream responses. The full repository validation suite was outside the original verification.
- The follow-up passed the native polling tests, repository-root `make validate`, and the Local application build. This Mac used installed Rust 1.93.0, above the project minimum, in place of the pinned Rust 1.100.0.

## Suggested Remediation Order

1. `AUDIT-002` restores playback for valid custom rain events.
2. `AUDIT-003` corrects the displayed and spoken sunrise comparison.

## Follow-up Checklist

- [x] `AUDIT-001` Keep full three-hour local deduplication while producing a valid bounded request.
- [ ] `AUDIT-002` Play valid rain events under all four field combinations.
- [ ] `AUDIT-003` Describe a zero whole-minute difference accurately in both output channels.
