use super::super::frame::{Canvas, Ink::*, eased};
pub fn icon(c: &mut Canvas) {
    c.begin();
    c.mov(-8., -2.9);
    c.quad(0.6, -4.2, -4., 3.);
    c.stroke(Silver, 1., 1., true);
    c.line((-4., -0.1), (-4., 3.2), Silver, 1., 0.85);
    c.line((-8.5, 3.2), (0.9, 3.2), Ivory, 1., 1.4);
    c.face(
        &[(-8.8, -2.9), (-7.4, -2.9), (-7., 6.7), (-9.1, 6.7)],
        Silver,
        1.,
        None,
    );
    c.line((-9., -3.3), (-7.2, -3.3), Ivory, 1., 1.);
    c.begin();
    c.mov(-0.9, 7.7);
    for (x, y) in [
        (-0.3, -5.4),
        (8.6, -5.4),
        (9.1, 7.7),
        (6.1, 7.7),
        (6.1, 3.2),
    ] {
        c.to(x, y);
    }
    c.quad(4.1, 0., 6.1, 1.7);
    c.quad(2.1, 3.2, 2.1, 1.7);
    c.to(2.1, 7.7);
    c.close();
    c.fill(Silver, 1.);
    for x in [0.9, 7.2] {
        c.face(
            &[(x - 1.75, -4.9), (x, -8.8), (x + 1.75, -4.9)],
            Slate,
            1.,
            Some(Ivory),
        );
    }
    c.line((0., -3.6), (8.4, -3.6), Ivory, 1., 0.8);
    c.rect(2.8, -2.8, 2.6, 1.35);
    c.fill(Slate, 1.);
    c.ellipse(7.2 - 1.65, 3. - 1.65, 3.3, 3.3);
    c.fill(Slate, 1.);
    c.stroke(Brass, 1., 0.9, false);
}
fn leaf(c: &mut Canvas, angle: f64) {
    c.translate(7.2, 3.);
    c.rotate(-angle);
    let depth = |x: f64| 4.6 - 2.5 * (x - 5.) / 41.;
    c.line((1.3, 0.), (48., 0.), Ivory, 1., 1.35);
    c.line((1.3, 0.), (5., depth(5.)), Silver, 1., 1.);
    c.line((5., depth(5.)), (46., depth(46.)), Silver, 1., 1.);
    c.line((46., depth(46.)), (48., 0.), Silver, 1., 1.);
    let bay = 41. / 3.;
    for i in 0..3 {
        let left = 5. + i as f64 * bay;
        let mid = left + bay / 2.;
        c.line((left, 0.), (mid, depth(mid)), Silver, 1., 0.9);
        c.line((mid, depth(mid)), (left + bay, 0.), Silver, 1., 0.9);
    }
}
pub fn scenery(c: &mut Canvas, t: f64, v: f64) {
    let angle = eased(t, 0.85, 3.73) * (0.66 + 0.025 * v);
    c.opacity(eased(t, 0., 0.38) * (1. - eased(t, 4.46, 5.29)));
    c.layer();
    c.save();
    leaf(c, angle);
    c.restore();
    c.translate(2. * 7.2 + 96. + 0.7, 0.);
    c.scale(-1., 1.);
    icon(c);
    leaf(c, angle);
    c.end_layer();
}
