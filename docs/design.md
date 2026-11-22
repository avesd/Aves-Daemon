# Aves Daemon Design Principles

Aves Daemon lets someone notice a small event in the world while staying with
the task at hand. A plane passes overhead. Rain picks up in Kyoto. A glance
should be enough to recognize what happened. Curiosity can do the rest.

## Give each event one recognizable gesture

Choose a small visual anchor whose movement belongs to the event. In a flyover,
the plane crosses the screen edge and reveals the route in its wake. In the rain
preview, the first drop lands just below the icon. A ripple spreads from that
point as the city, change in rainfall, and local time appear. Each gesture gives
the eye a place to start and leads it naturally to the summary.

## Let the reader learn the panel once

Every event uses the same panel component. The panel owns its screen position,
width, icon slot, text baseline, and hover area. Each event supplies its gesture,
the order in which its fields appear, and its details. Someone who has learned
where to look for a flight can find the next rain summary in exactly the same
place. When details open below the summary, the line they were reading stays put.

## Give variation a cause and a boundary

In the rain preview, the first drop has a dependable landing point. Later drops
vary in timing and position, and each ripple begins where its own drop lands.
Leave visible space between the widest ripple and the icon. This gives each
shower its own rhythm while the words and the area that responds to the pointer
remain steady.

## Let the viewer choose how long to stay

The gesture settles into one readable line. Hovering holds the summary and
reveals details such as the aircraft model or the local observation time.
Moving away lets the event fade. Clicks pass through to the app underneath,
which keeps keyboard focus. With Reduce Motion enabled, the complete summary
appears in place and the same details are available on hover.

When reviewing a new event, try it while reading something else. Can you
recognize it out of the corner of your eye? If you lean in, is there one more
thing worth learning? If you keep reading, can the event pass on its own?

For preview controls and platform-specific behavior, see the [macOS client guide](../apps/macos/README.md).
