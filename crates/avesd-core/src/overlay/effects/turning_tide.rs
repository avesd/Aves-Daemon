use super::super::frame::{Canvas, Ink::*, eased};

pub fn draw(c: &mut Canvas, icon: bool, t: f64, v: f64, room: f64, rising: bool) {
    let fall = eased(t, 1., 5.15);
    let fall = if rising { 1. - fall } else { fall };
    let x = (room - 28.).clamp(32., 125.) + v * 4.;
    let level = 5. + 42. * fall;
    let roll = -0.035 + 0.067 * fall + (t * 1.8).sin() * 0.018 * (1. - fall);
    let (sin, cos) = roll.sin_cos();
    let dx = x - 13. * cos + 2.8 * sin - 3.;
    let dy = level - 13. * sin - 2.8 * cos - 0.8;
    let sag = (22. + v * 1.3) * (1. - fall).powf(0.68) + 0.35;
    let point = |u: f64| (3. + dx * u, 0.8 + dy * u + 4. * sag * u * (1. - u));
    let rope = |c: &mut Canvas, a: f64, b: f64| {
        let (sx, sy) = point(a);
        let (ex, ey) = point(b);
        c.begin();
        c.mov(sx, sy);
        c.quad(
            ex,
            ey,
            sx + dx * (b - a) / 2.,
            sy + (dy + 4. * sag * (1. - 2. * a)) * (b - a) / 2.,
        );
        c.stroke(Brass, 1., 1.45, true);
    };
    let collar = 5.6 / dx;
    if icon {
        c.round_rect(-8., -6., 3., 12., 1.);
        c.fill(Slate, 1.);
        c.stroke(Silver, 1., 0.85, false);
        c.line((-5.3, -0.9), (-2.9, -0.9), Silver, 1., 1.45);
        c.ellipse(-3.5, -3.5, 7., 8.);
        c.stroke(Ivory, 1., 1.4, false);
        rope(c, 0., collar);
        return;
    }
    c.opacity(eased(t, 0., 0.46) * (1. - eased(t, 6.16, 7.35)));
    c.line(
        (x - 22., level + 5.6),
        (x - 6., level + 5.6),
        Silver,
        0.48,
        0.75,
    );
    c.line(
        (x + 4., level + 5.6),
        (x + 21., level + 5.1),
        Silver,
        0.45,
        0.75,
    );
    c.line(
        (x - 11., level + 8.3),
        (x + 4., level + 8.3),
        Silver,
        0.35,
        0.65,
    );
    c.save();
    c.translate(x, level);
    c.rotate(roll);
    c.begin();
    c.mov(-16., -3.1);
    c.quad(15.4, -2.1, -6., -0.8);
    c.to(13.5, 2.);
    c.quad(-16., -3.1, -5., 8.6);
    c.close();
    c.fill(Slate, 1.);
    c.stroke(Silver, 1., 1., false);
    c.begin();
    c.mov(-15., -2.7);
    c.quad(15., -2., -7., -0.5);
    c.stroke(Brass, 1., 1.15, false);
    c.face(
        &[(-3., -2.), (-1.4, -7.2), (6., -7.2), (8.4, -2.2)],
        Ivory,
        1.,
        Some(Slate),
    );
    c.face(
        &[(-0.7, -6.3), (1.5, -6.3), (1.5, -3.8), (-1.4, -3.8)],
        Slate,
        1.,
        None,
    );
    c.face(
        &[(2.7, -6.3), (5.4, -6.3), (6.3, -3.8), (2.7, -3.8)],
        Slate,
        1.,
        None,
    );
    c.line((-2.1, -7.45), (6.3, -7.45), Silver, 1., 0.9);
    c.line((-13., -2.8), (-12.8, -3.8), Ivory, 1., 1.);
    c.restore();
    rope(c, collar, 1.);
}
