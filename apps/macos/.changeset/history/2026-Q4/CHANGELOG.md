# Changelog

## 0.1.0

- Show each flight callsign once in its summary.
  Change intent: `flight-summary` (patch).

- Play incoming events with adaptive intervals and remember played events for three hours. Choose a place or use the Mac’s approximate location for nearby flights.
  Change intent: `live-playback` (minor).

- Prepare events and trigger personal notes through a local Murmur server. Arrange polling sources in the order they take turns.
  Change intent: `local-murmur-server` (minor).

- Try a sample flyover at the selected duration in Display settings and see the client version in About.
  Change intent: `macos-flyover` (minor).

- Check for software updates from the menu bar and choose automatic checks and installation in Preferences on update-enabled builds.
  Change intent: `macos-software-updates` (minor).

- Label UTC event times explicitly in the overlay.
  Change intent: `overlay-utc` (patch).

- Show rain showers in the same screen-edge panel as aircraft flyovers.
  Change intent: `rain-preview` (minor).

- Show sunrises, bridge lifts, turning tides, and last trains at the screen edge.
  Change intent: `world-event-previews` (minor).
