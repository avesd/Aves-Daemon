#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

uint64_t avesd_next_click_count(uint64_t current);

typedef struct {
    double start_ms, fall_ms, decay_ms, offset, depth, radius;
} AvesdRainDrop;

typedef struct {
    AvesdRainDrop drops[4];
    uint32_t count;
    double drift, duration_ms;
} AvesdRainShower;

enum { AVESD_RAIN_BEAD, AVESD_RAIN_LINE, AVESD_RAIN_ELLIPSE, AVESD_RAIN_ARC };

// x/y are relative to the icon center, in logical pixels, positive down.
// Bead: origin and size. Line: endpoints. Ellipse/arc: center and radii.
// Arcs start on the positive x axis and advance clockwise in degrees.
typedef struct {
    uint32_t kind;
    double x, y, a, b, opacity, stroke, start_deg, sweep_deg;
} AvesdRainShape;

typedef struct {
    AvesdRainShape shapes[5];  // Paint the first count entries in order.
    uint32_t count;
    double field_opacity[4];  // Icon, city, rain trend, local time.
} AvesdRainFrame;

AvesdRainShower avesd_rain_shower(uint64_t seed);
// Pass the unmodified shower returned for this preview.
AvesdRainFrame avesd_rain_frame(const AvesdRainShower *shower, double elapsed_ms, bool reduced);

enum {
    AVESD_OP_BEGIN = 0,
    AVESD_OP_MOVE = 1,
    AVESD_OP_LINE_TO = 2,
    AVESD_OP_QUAD = 3,
    AVESD_OP_CLOSE = 4,
    AVESD_OP_RECT = 5,
    AVESD_OP_ROUND_RECT = 6,
    AVESD_OP_ELLIPSE = 7,
    AVESD_OP_ARC = 8,
    AVESD_OP_FILL = 9,
    AVESD_OP_STROKE = 10,
    AVESD_OP_CLIP = 11,
    AVESD_OP_SAVE = 12,
    AVESD_OP_RESTORE = 13,
    AVESD_OP_TRANSLATE = 14,
    AVESD_OP_ROTATE = 15,
    AVESD_OP_SCALE = 16,
    AVESD_OP_OPACITY = 17,
    AVESD_OP_BEGIN_LAYER = 18,
    AVESD_OP_END_LAYER = 19,
    AVESD_OP_GRADIENT = 20,
    AVESD_OP_STOP = 21,
    AVESD_OP_FILL_GRADIENT = 22,
    AVESD_OP_STROKE_GRADIENT = 23,
    AVESD_OP_GLYPH = 24,
    AVESD_OP_SYMBOL = 25,
    AVESD_OP_SHADOW = 26,
    AVESD_OP_TRANSFORM_ARC = 27
};
enum {
    AVESD_INK_WHITE = 0,
    AVESD_INK_IVORY = 1,
    AVESD_INK_SILVER = 2,
    AVESD_INK_BRASS = 3,
    AVESD_INK_SLATE = 4,
    AVESD_INK_BRICK = 5,
    AVESD_INK_BLACK = 6,
    AVESD_INK_CLEAR = 7
};
enum {
    AVESD_PREVIEW_FLYOVER,
    AVESD_PREVIEW_RAIN,
    AVESD_PREVIEW_SUNRISE,
    AVESD_PREVIEW_BRIDGE_LIFT,
    AVESD_PREVIEW_TURNING_TIDE,
    AVESD_PREVIEW_LAST_TRAIN
};

// Coordinates are logical pixels relative to the icon center, positive y down.
// Begin clears the path. Rect, RoundRect, Ellipse and Arc replace it.
// Move/LineTo use x,y; Quad uses x,y for the endpoint and a,b for the control.
// Rectangles use origin and size; RoundRect.tag is corner radius in thousandths.
// Arc uses start/sweep degrees; TransformArc applies center and radii to its path.
// Fill/Stroke tag indexes ink; x is alpha, y is width, a selects round caps.
// Save/Restore scope context; Rotate uses radians. Layers composite together.
// Gradient takes endpoints; following Stop commands give evenly spaced ink/alpha pairs.
// Glyph.tag is a Unicode scalar, x is point size, y is ink. Symbol 0 is a drop
// in the given bounds; 1 is a centered plane of width a with native aspect.
// Shadow supplies alpha, radius and vertical offset in x,y,a respectively.
typedef struct { uint32_t op, tag; double x,y,a,b; } AvesdCommand;
typedef struct {
    double progress, expansion, opacity, open_fraction, surface_opacity, traced_fraction, trace_opacity;
    double reveal_edge, fields[4];
    bool alive, animating;
} AvesdPanel;
typedef struct {
    AvesdPanel panel;
    const AvesdCommand *icon; size_t icon_count;
    const AvesdCommand *scenery; size_t scenery_count;
} AvesdOverlayFrame;
typedef struct { uint64_t seed; double hold_ms, width, anchor_x; bool reduced; } AvesdOverlayOptions;
typedef struct AvesdOverlaySession AvesdOverlaySession;

// The input buffer must contain size initialized bytes and stay readable and
// unmodified until create returns. Each JSON record describes one event. NULL means invalid or unsupported.
// Previews use the same decoder. Destroy each successful handle exactly once.
AvesdOverlaySession *avesd_overlay_create(const uint8_t *json, size_t size, AvesdOverlayOptions options);
AvesdOverlaySession *avesd_overlay_preview(uint32_t kind, AvesdOverlayOptions options);
void avesd_overlay_destroy(AvesdOverlaySession *session);
// Content is a UTF-8 JSON presentation, borrowed for the session lifetime.
const char *avesd_overlay_content(const AvesdOverlaySession *session);
// Advance with monotonic milliseconds since start and native hover hit testing.
// True means the frame changed. A session is used on one playback thread.
bool avesd_overlay_advance(AvesdOverlaySession *session, double elapsed_ms, bool inside);
// Advances once and reports differences from the immediately preceding frame.
// Read a full frame after creating a session. For subsequent updates, copy each
// changed layer (including an empty layer) and retain owned copies of the others.
typedef struct { bool panel, icon, scenery; } AvesdFrameChanges;
AvesdFrameChanges avesd_overlay_advance_changes(AvesdOverlaySession *session, double elapsed_ms, bool inside);
// Buffers are borrowed until the next advance or destroy. Copy for deferred painting.
AvesdOverlayFrame avesd_overlay_frame(const AvesdOverlaySession *session);

#ifdef __cplusplus
}
#endif
