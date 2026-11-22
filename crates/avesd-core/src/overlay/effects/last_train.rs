use super::super::frame::{Canvas, Ink::*, eased};
use std::f64::consts::PI;

fn flap(c: &mut Canvas, old: Option<char>, new: Option<char>, turn: f64, main: bool) {
    let (w, h) = if main { (17.2, 17.4) } else { (14.5, 15.5) };
    c.round_rect(-w / 2., -h / 2., w, h, 1.6);
    c.fill(Slate, 1.);
    c.stroke(
        if main { Brass } else { Silver },
        if main { 0.8 } else { 0.65 },
        0.85,
        false,
    );
    let half = |c: &mut Canvas, ch: Option<char>, upper: bool, scale: f64, moving: bool| {
        c.save();
        c.round_rect(-w / 2., -h / 2., w, h, 1.6);
        c.clip();
        c.scale(1., scale);
        c.rect(-w / 2., if upper { -h / 2. } else { 0. }, w, h / 2.);
        c.clip();
        if moving {
            c.rect(-w / 2. + 0.55, -h / 2. + 0.55, w - 1.1, h - 1.1);
            c.fill(Slate, 1.);
            c.fill(Black, (1. - scale) * 0.46);
        }
        if let Some(ch) = ch {
            c.glyph(
                ch,
                if main { 12. } else { 13. },
                if main { Brass } else { Ivory },
            );
        }
        c.restore();
    };
    half(c, new, true, 1., false);
    half(c, if turn == 1. { new } else { old }, false, 1., false);
    let tilt = (PI * turn).cos().abs();
    if tilt > 0.015 {
        half(
            c,
            if turn < 0.5 { old } else { new },
            turn < 0.5,
            tilt,
            true,
        );
    }
    if turn > 0.5 && turn < 1. {
        let glint = (PI * (turn - 0.5) * 2.).sin();
        let edge = (h / 2. - 0.9) * tilt;
        c.line(
            (-w / 2. + 1.5, edge),
            (w / 2. - 2., edge),
            Ivory,
            glint * if main { 0.67 } else { 0.38 },
            0.75,
        );
    }
    c.line(
        (-w / 2. + 0.6, 0.25),
        (w / 2. - 0.6, 0.25),
        Slate,
        0.82,
        0.65,
    );
}
pub fn icon(c: &mut Canvas, t: f64) {
    flap(c, Some('発'), Some('終'), eased(t, 2.41, 2.68), true);
}
pub fn scenery(c: &mut Canvas, t: f64, v: f64, destination: &str, local_time: &str) {
    c.opacity(eased(t, 0., 0.26) * (1. - eased(t, 2.23, 2.70)));
    c.line((9., -9.5), (138., -9.5), Silver, 0.6, 1.);
    let dest = destination.chars().take(2);
    let n = dest.clone().count();
    for (i, ch) in dest
        .chain(local_time.chars().filter(char::is_ascii_digit))
        .enumerate()
    {
        let ix = i as f64;
        let start = 1.32 + ix * (0.068 + v * 0.008) + if i >= n { 0.13 } else { 0. };
        c.save();
        c.translate(
            21. + ix * 17. + if i >= n { 5. } else { 0. } + if i >= n + 2 { 5. } else { 0. },
            0.,
        );
        flap(c, Some(ch), None, eased(t, start, start + 0.20), false);
        c.restore();
    }
    c.opacity(1. - eased(t, 1.63, 1.84));
    for y in [-2., 2.] {
        c.ellipse(87.25 + (n as f64 - 2.) * 17., y - 0.75, 1.5, 1.5);
        c.fill(Ivory, 1.);
    }
}
