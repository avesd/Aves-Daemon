# Aves Daemon for macOS

Use the Node version in the root `.nvmrc` and run `pnpm install --frozen-lockfile` at the repository root before the first build. The macOS build generates its menu bar and settings artwork from the pinned `@avesd/logo/geometry` square and standard variants. The compiled application contains the paths and renders the brand mark offline.

Run `make run` here to build and open `.build/Aves Daemon.app`. Click the bird in the macOS menu bar and choose **Preview Flyover**. The app runs as a menu bar accessory without a Dock icon. The preview uses a sample United Airlines flight from Los Angeles to Sydney. The plane crosses the upper-right corner of the display containing the pointer and reveals its carrier mark, route, callsign, and aircraft type in its wake. Reduce Motion shows the summary in place.

Choose **Preview Rain** for a sample Kyoto observation at 18:42 JST. Each preview generates a fresh shower. The first drop lands below the icon slot and sends out a ripple as the city, rain trend, and time appear in sequence. The smaller drops vary in timing and position. All previews share the same screen position, summary width, hover behavior, and display duration. Reduce Motion shows the complete summary in place.

All six previews use the [shared event and playback contracts](../../README.md#event-data-and-playback). The [session adapter](Sources/AvesdOverlay/Overlay/OverlaySession.swift) measures the native hover area and reads one frame per tick. The [Canvas renderer](Sources/AvesdOverlay/Overlay/ArtworkCanvas.swift) paints the two artwork layers while SwiftUI manages text, accessibility, and window layout.

Four other menu commands preview sample events. The summary row provides a 20-point icon slot and a separate information slot. Each gesture shares its origin with the icon and can extend into the surrounding panel. The resting icon stays in the row when the details open.

| Menu command | Sample event | Gesture |
| --- | --- | --- |
| **Preview Sunrise** | Lisbon at 07:26 | First light catches a lighthouse lantern and casts a long shadow from the tower. |
| **Preview Bridge Lift** | Tower Bridge at 15:40 | Two rigid truss leaves rotate around their bearings. The near stone tower and its complete suspension approach remain in the icon slot. |
| **Preview Turning Tide** | Saint-Malo at 16:08 | A moored boat drops with the tide and draws the line taut between its bow and the quay ring. |
| **Preview Last Train** | Ueno Station at 23:54 | The destination and time flip to blank, and the last flap catches the light as it turns from 発 to 終. |

By default the trail remains for five seconds. Rest the pointer on the summary for 150 ms to open the flight details. A fine line traces the frame clockwise from the aircraft type as the background fills in behind the stationary summary. The highlight fades at the end of the 460 ms transition. Hovering pauses dismissal. Moving away reverses the transition and resumes dismissal. Reduce Motion switches directly between the closed and open states. The panel passes clicks through and preserves keyboard focus. Starting another preview replaces the current one.

The click-through AppKit panel hosts a SwiftUI view. The summary stays anchored as the frame reveals the details below it. SwiftUI lays out the text and draws the plane and contrails in a Canvas.

## Typography

The Settings wordmark uses the system's Futura Medium. The flyover uses the macOS serif face for airline names and the system UI face for details, including their localized Chinese glyphs. Flight codes use IBM Plex Mono Medium, the only bundled font. The app registers it for its own process. The font and its OFL notice come from the [pinned Google Fonts distribution](https://github.com/google/fonts/tree/06bfe0d62a98375cb09c942fa18e68bd32cff057/ofl/ibmplexmono).

## Settings

Choose **Settings…** from the menu bar, or reopen the running app from Finder. The same settings window comes to the front. Closing it leaves the menu bar app running. Choose **Quit Aves Daemon** to exit.

Select a display duration of 3, 5, or 8 seconds and click **Preview** in the **Flight preview** or **Rain preview** row to try it. The **World event preview** menu plays any of the four world events. The Preferences footer pairs the bird with the Aves Daemon wordmark. The bird traces in when the window opens. Hovering the footer or focusing it with the keyboard slides the D left and fades it into a lowercase d while the suffix stays in place. The bird nods and morphs to the standard mark. The lower-right corner and About sheet show the release version from [version.json](version.json) and the bundle build number. The [client release workflow](../../README.md#macos-client-releases) manages the release version. Activating any part of the footer opens the About sheet, which includes the product website. Leaving restores the product signature. Reduce Motion switches directly between the two states. Settings persist across launches. The **Airline logos** section controls preloading, shows the number and size of cached marks, and can clear those marks. Downloading an individual flight's logo on demand still works with preloading off.

## Airline marks

With preloading enabled, the first preview warms the cache for United, Delta, and Lufthansa. The client requests monochrome SVGs from the [Soaring Symbols 0.4 release line](https://github.com/soaring-symbols/soaring-symbols#cdn). Its [brand asset notice](https://github.com/soaring-symbols/soaring-symbols/blob/main/DISCLAIMER.md) describes rights in the individual marks.

SVGs live under the user caches directory in `<bundle-id>/airline-logos/`. The standalone Swift executable uses `ai.avesd.daemon` as its identifier when it has no bundle ID. Cached images older than 30 days are refreshed in the background. The cache evicts the oldest SVGs above 4 MiB. When a logo is unavailable at reveal time, the airline code stays in place for the entire pass.
