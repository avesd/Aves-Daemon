use super::super::frame::{Canvas, Ink::*, eased};

pub fn icon(c: &mut Canvas, t: f64) {
    let light = eased(t, 0.38, 1.75);
    c.face(
        &[(-5.2, 8.3), (-3., -0.9), (3., -0.9), (5.2, 8.3)],
        Silver,
        1.,
        Some(Slate),
    );
    c.face(
        &[(1.2, -0.8), (3., -0.8), (5., 8.), (2.4, 8.)],
        Slate,
        0.46,
        None,
    );
    c.face(
        &[(-3.65, 2.2), (3.65, 2.2), (4.05, 4.1), (-4.05, 4.1)],
        Brick,
        1.,
        None,
    );
    c.face(
        &[(-3.25, -2.2), (-3.25, -6.), (3.25, -6.), (3.25, -2.2)],
        Slate,
        1.,
        Some(Silver),
    );
    c.rect(-2.5, -5.5, 2.2, 2.65);
    c.fill(Brass, light);
    c.line((-3., -0.6), (-5., 7.8), Brass, light, 1.);
    c.face(
        &[(-5., -6.1), (-0.3, -9.), (4.8, -6.1)],
        Slate,
        1.,
        Some(Ivory),
    );
    c.line((-5.2, -1.), (5.2, -1.), Ivory, 1., 1.);
    for x in [-5.2, 5.2] {
        c.line((x, -2.8), (x, -1.), Silver, 1., 0.8);
    }
    c.round_rect(-1., 5.4, 2., 3.4, 0.8);
    c.fill(Slate, 1.);
    c.line((-6.2, 8.6), (6.1, 8.6), Ivory, 1., 1.);
}
pub fn scenery(c: &mut Canvas, t: f64, v: f64, room: f64) {
    let light = eased(t, 0.38, 1.75);
    let len = ((room - 12.).min(142.) + v * 7.) * eased(t, 0.9, 2.25);
    let y = 9. + len * (0.29 - 0.15 * eased(t, 1.9, 4.22));
    c.opacity(1. - eased(t, 4.55, 6.1));
    c.begin();
    c.mov(-59., 7.);
    c.to(107., 7.);
    c.gradient(
        (-59., 7.),
        (107., 7.),
        &[(Clear, 1.), (Silver, 0.52), (Clear, 1.)],
    );
    c.stroke_gradient(0.75 * eased(t, 0., 0.62));
    c.save();
    c.rect(-45., -12., 20., 19.);
    c.clip();
    c.ellipse(-40.1, 6.9 - 7. * light, 10.2, 10.2);
    c.fill(Brass, 0.82 * light);
    c.restore();
    c.line((-32., 10.), (-26., 10.), Brass, 0.62 * light, 0.7);
    c.line((-38., 12.), (-31., 12.), Brass, 0.44 * light, 0.7);
    if len > 1. {
        c.polygon(&[
            (-5., 8.),
            (len - 4., y - 1.2),
            (len + 2., y + 0.5),
            (len - 2., y + 2.1),
            (4., 9.),
        ]);
        c.gradient((0., 8.), (len, y), &[(Black, 0.64), (Black, 0.08)]);
        c.fill_gradient();
    }
}
