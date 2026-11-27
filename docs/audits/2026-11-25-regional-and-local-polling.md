# Aves Daemon macOS polling audit — 2026-11-25

## Summary

The joint Aves Daemon and Aves Daemon Service audit found three desktop-owned defects. A regional poll can miss its scheduled day, an unplayed local note can expire behind already-played notes, and a slow source can delay local playback past the note's deadline. The first two findings are P2 and the third is P3.

## Scope and Method

Reviewed the Aves Daemon macOS worktree at `a4b82e7`, including regional endpoint selection, scheduling, the local SQLite queue, playback history and the native playback entry point. The service boundary was Murmur's regional event response. The local server is an optional source that participates in the same polling round. The November 24 audit already covers oversized playback-history requests. The queue finding below occurs even when all requests satisfy the 64-ID limit. [Prior audit](2026-11-24-murmur-playback.md#L11)

## Findings

### AUDIT-001 — A daily regional poll can miss an entire interval during location refresh

- **Class, severity and confidence** Defect, P2, high confidence.
- **Evidence** The fixed interval can be 1,440 minutes. After that wait, the poller requests a location refresh and immediately builds the source list. A device fix aged 24 hours or being refreshed yields no cell, which removes the regional endpoint from the round. [Interval limits](../../apps/macos/Sources/AvesdOverlay/DaemonPreferences.swift#L38) · [Polling loop](../../apps/macos/Sources/AvesdOverlay/EventPolling.swift#L60) · [Cell availability](../../apps/macos/Sources/AvesdOverlay/EventRegion.swift#L46) · [Regional endpoint](../../apps/macos/Sources/AvesdOverlay/DaemonPreferences.swift#L29)
- **Decision boundary** Device mode refreshes a 24-hour-old fix. Fixed polling uses the user's selected base interval. [Location contract](../../apps/macos/README.md#L42) · [Rhythm settings](../../apps/macos/README.md#L88)
- **Behavior and impact** Start a daily schedule after acquiring a device fix. If the Mac stays awake without an intervening refresh, the first due round skips Murmur. A successful refresh in the same cell publishes the new fix, but the scheduler observes only changes in cell ID. The next opportunity can be another 24 hours away. A sufficiently recent fix at a later poll allows recovery. Fixed places have no fix-age cutoff. [Refresh and callback](../../apps/macos/Sources/AvesdOverlay/EventRegion.swift#L93) · [Saving the fix](../../apps/macos/Sources/AvesdOverlay/EventRegion.swift#L131) · [Scheduler subscription](../../apps/macos/Sources/AvesdOverlay/main.swift#L101)
- **Remediation and verification** Retain the due regional request while an authorized refresh is in progress and issue it once a usable cell arrives, including an unchanged cell. Keep fixed sources and the one-play-per-round rule working. Verify the 24-hour boundary, same-cell completion, refresh failure and cancellation when the regional source is disabled.

### AUDIT-002 — An unplayed note can expire behind 65 already-played local notes

- **Class, severity and confidence** Defect, P2, high confidence.
- **Evidence** The client sends the 64 most recently played IDs known to the source. SQLite returns the newest inserted row outside that list. The client suppresses a duplicate using its complete history and retains the original play time, so the next round excludes the same 64 IDs. [Request construction](../../apps/macos/Sources/AvesdOverlay/EventPolling.swift#L85) · [Duplicate handling](../../apps/macos/Sources/AvesdOverlay/EventPolling.swift#L112) · [SQLite selection](../../apps/macos/Sources/AvesdOverlay/LocalServer/LocalEventStore.swift#L93)
- **Decision boundary** Pull-only use is supported. A read leaves the candidate available, and external callers can send up to 64 played IDs. Playback history lasts three hours. [Pull-only use](../../apps/macos/README.md#L48) · [GET contract](../../apps/macos/README.md#L55) · [Playback history](../../apps/macos/README.md#L95)
- **Behavior and impact** Prepare 66 notes together, use only the local source and poll every minute. After 65 successful rounds, the oldest unplayed note sits behind 65 played candidates. Every valid request leaves at least one newer candidate eligible in SQLite. The note inserted first also reaches its default three-hour expiry first, so it can be lost despite ample remaining polling time. Restarting the app preserves both the queue and history. [Local expiry](../../apps/macos/Sources/AvesdOverlay/LocalServer/LocalEventStore.swift#L76) · [Reloaded history](../../apps/macos/Sources/AvesdOverlay/EventPolling.swift#L49)
- **Remediation and verification** Use the desktop client's complete playback history when selecting from its own local store. Keep the public GET limit and nondestructive reads for other callers. Verify that 66 prepared notes play exactly once within their lifetime and that an external reader can still retrieve a note played by the app.
- **Status** Resolved. The desktop client selects a prepared event using its full playback history and the shared local store. Loopback readers retain the 64-ID limit and nondestructive reads. [Internal queue](../../apps/macos/Sources/AvesdOverlay/LocalServer/LocalEventStore.swift#L103)

### AUDIT-003 — A local candidate can start playback after its deadline

- **Class, severity and confidence** Defect, P3, high confidence.
- **Evidence** The local store checks expiry when serving a read. The poller decodes only the event ID and collects all source responses before choosing a candidate. The final playback check examines history and selection state without consulting the deadline. [Local read](../../apps/macos/Sources/AvesdOverlay/LocalServer/LocalEventStore.swift#L93) · [Response decoding](../../apps/macos/Sources/AvesdOverlay/EventPolling.swift#L168) · [Concurrent collection](../../apps/macos/Sources/AvesdOverlay/EventPolling.swift#L85) · [Playback decision](../../apps/macos/Sources/AvesdOverlay/EventPolling.swift#L112)
- **Decision boundary** A prepared event can declare an RFC 3339 deadline. An update without an explicit expiry preserves the stored deadline. [Candidate expiry](../../apps/macos/README.md#L58)
- **Behavior and impact** A local note can be eligible when returned and expire while the same round waits for Murmur. It then starts playback and enters three-hour history. A later store read removes it, after the stale notification has already appeared. [Loopback response](../../apps/macos/Sources/AvesdOverlay/LocalServer/LocalMurmurServer.swift#L89) · [Native presentation](../../apps/macos/Sources/AvesdOverlay/main.swift#L197)
- **Remediation and verification** Carry the local store's effective deadline through selection and check it immediately before playback. Continue to the next candidate when a deadline passes. Verify explicit and default deadlines, an update that retains a prior deadline, and another source with a still-valid event in the same round.
- **Status** Resolved. The local deadline is checked when selecting a candidate and before its panel appears. If it passes during a replacement fade, polling can still select a valid event in the same round. [Polling](../../apps/macos/Sources/AvesdOverlay/EventPolling.swift#L87) · [Presentation](../../apps/macos/Sources/AvesdOverlay/Overlay/OverlaySession.swift#L123)

## Verification Record

- Compiled the worktree's Swift poller, preferences, region selection, SQLite store and overlay session. Used in-memory preferences, temporary SQLite files and synthetic responses. The harness exercised the native playback session without displaying an AppKit window.
- At exactly 24 hours of fix age, the official source made zero fetches. Saving a fresh fix in the same cell restored availability and emitted zero additional distinct cell IDs. A fixed-place control made one fetch. This check simulated fix timestamps. Core Location hardware, an actual day-long wait and later-day recovery were outside the runtime check.
- Inserted 66 distinct notes and ran 70 accelerated rounds. The first 65 notes played newest first. The next five reads each returned the already-played newest note with 64 exclusions. The oldest note never played. The expiry outcome follows from insertion order and stored deadlines.
- Returned a local note with one second remaining alongside a synthetic two-second Murmur response. The native session accepted the note about one second after expiry. A fresh SQLite read at that point returned no candidate. Live Murmur and the full repository validation suite were outside these checks.

## Suggested Remediation Order

1. `AUDIT-001` restores scheduled delivery from the default regional source in device-location mode.
2. `AUDIT-002` lets the desktop client reach eligible local notes throughout their lifetime.
3. `AUDIT-003` enforces local deadlines at the final playback decision.

## Follow-up Checklist

- [ ] `AUDIT-001` Issue the due regional poll after a same-cell refresh at the age limit.
- [ ] `AUDIT-002` Play all 66 locally prepared notes exactly once and preserve the public GET contract.
- [ ] `AUDIT-003` Skip a candidate that expires during its round and leave it out of playback history.
