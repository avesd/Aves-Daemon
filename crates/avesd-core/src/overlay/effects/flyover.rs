use super::super::frame::{Canvas, Ink::*};

const PLANE_WIDTH: f64 = 27.;
const TRAIL_GAP: f64 = 10.;
const LONG_TRAIL: f64 = 38.;
const SHADOW_CLEARANCE: f64 = 4.;

pub(super) fn center_x(width: f64, progress: f64) -> f64 {
    let start = -PLANE_WIDTH / 2. - SHADOW_CLEARANCE;
    let end = width + TRAIL_GAP + LONG_TRAIL + SHADOW_CLEARANCE;
    start + (end - start) * progress
}

pub fn scenery(c: &mut Canvas, center: f64) {
    c.shadow(0.5, 1.5, 0.);
    for (y, length) in [(-2., LONG_TRAIL), (2., 30.)] {
        let tip = (center - TRAIL_GAP, y);
        let tail = (tip.0 - length, y);
        c.begin();
        c.mov(tail.0, y);
        c.to(tip.0, y);
        c.gradient(tail, tip, &[(Clear, 1.), (White, 0.82)]);
        c.stroke_gradient(1.);
    }
    // A zero height asks the native renderer to preserve the symbol's aspect ratio.
    c.symbol(1, center, 0., PLANE_WIDTH, 0.);
}
