use super::super::frame::{Canvas, Ink::*};

pub fn scenery(c: &mut Canvas, nose: f64) {
    c.shadow(0.5, 1.5, 0.);
    for (y, length) in [(-2., 38.), (2., 30.)] {
        let tip = (nose - 10., y);
        let tail = (tip.0 - length, y);
        c.begin();
        c.mov(tail.0, y);
        c.to(tip.0, y);
        c.gradient(tail, tip, &[(Clear, 1.), (White, 0.82)]);
        c.stroke_gradient(1.);
    }
    // A zero height asks the native renderer to preserve the symbol's aspect ratio.
    c.symbol(1, nose, 0., 27., 0.);
}
