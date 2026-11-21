# Avesd for macOS

Run `make run` from this directory to build the Rust library and launch the AppKit overlay. The ring and caption appear near the upper-right corner of the display containing the pointer.

Click the colored ring to increment the counter or drag it to move both pieces. The caption, center hole, and outer corners allow clicks through to the application underneath. The panels keep keyboard focus in the active application.

The Swift click handler calls `avesd_next_click_count` through the `CAvesdCore` module. The `avesd-ffi` dynamic library exposes the C ABI and delegates to `avesd-core`. Swift stores the returned `UInt64` and updates the caption on the main thread. Dragging and window management stay in AppKit.

Use the **Avesd** menu bar item to reset the position or quit.
