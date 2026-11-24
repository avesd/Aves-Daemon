use super::super::frame::{Canvas, Ink::*, eased};

pub fn icon(c: &mut Canvas, t: f64) {
    c.polygon(&[(-6., -8.), (2., -8.), (7., -3.), (7., 8.), (-6., 8.)]);
    c.fill(Slate, 1.);
    c.stroke(Ivory, 0.95, 1.2, true);
    c.line((2., -8.), (2., -3.), Ivory, 0.75, 1.);
    c.line((2., -3.), (7., -3.), Ivory, 0.75, 1.);
    for (y, end, start) in [(0., 4., 0.), (4., 1., 0.22)] {
        let length = (end + 3.) * eased(t, start, start + 0.35);
        c.line((-3., y), (-3. + length, y), Ivory, 0.95, 1.1);
    }
}
