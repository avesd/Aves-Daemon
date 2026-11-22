//! Seeded screen-edge rain. Times are milliseconds and positions are logical
//! pixels relative to the icon center, with positive y pointing down.
#[derive(Clone, Copy, Default)]
#[repr(C)]
pub struct RainDrop {
    pub start_ms: f64,
    pub fall_ms: f64,
    pub decay_ms: f64,
    pub offset: f64,
    pub depth: f64,
    pub radius: f64,
}

#[repr(C)]
#[derive(Default)]
pub struct RainShower {
    pub drops: [RainDrop; 4],
    pub count: u32,
    pub drift: f64,
    pub duration_ms: f64,
}

use super::Samples;

#[repr(u32)]
#[derive(Clone, Copy, Default, Debug, PartialEq)]
pub enum ShapeKind {
    #[default]
    Bead,
    Line,
    Ellipse,
    Arc,
}

#[repr(C)]
#[derive(Default, Clone, Copy)]
pub struct RainShape {
    pub kind: ShapeKind,
    pub x: f64,
    pub y: f64,
    pub a: f64,
    pub b: f64,
    pub opacity: f64,
    pub stroke: f64,
    pub start_deg: f64,
    pub sweep_deg: f64,
}

#[repr(C)]
#[derive(Default)]
pub struct RainFrame {
    pub shapes: [RainShape; 5],
    pub count: u32,
    pub field_opacity: [f64; 4],
}

impl RainFrame {
    fn push(&mut self, shape: RainShape) {
        self.shapes[self.count as usize] = shape;
        self.count += 1;
    }
}

impl RainShower {
    pub fn new(seed: u64) -> Self {
        let mut rng = Samples(seed);
        let mut shower = Self {
            drift: rng.range(-3.0, 3.0),
            ..Self::default()
        };
        let first = RainDrop {
            fall_ms: rng.range(320.0, 400.0),
            decay_ms: 920.0,
            depth: 20.0,
            radius: 17.5,
            ..RainDrop::default()
        };
        shower.drops[0] = first;
        shower.duration_ms = first.fall_ms + first.decay_ms;
        let mut start_ms = first.fall_ms + rng.range(180.0, 310.0);
        let mut side = if rng.next() & 1 == 0 { -1.0 } else { 1.0 };
        shower.count = 3 + (rng.next() & 1) as u32;
        for drop in &mut shower.drops[1..shower.count as usize] {
            *drop = RainDrop {
                start_ms,
                fall_ms: rng.range(130.0, 200.0),
                decay_ms: rng.range(540.0, 750.0),
                offset: side * rng.range(3.0, 8.0),
                depth: rng.range(20.0, 23.0),
                radius: rng.range(6.0, 10.0),
            };
            shower.duration_ms = shower
                .duration_ms
                .max(start_ms + drop.fall_ms + drop.decay_ms);
            start_ms += rng.range(240.0, 380.0);
            side = -side;
        }
        shower
    }

    pub fn frame(&self, elapsed_ms: f64, reduced: bool) -> RainFrame {
        let mut frame = RainFrame::default();
        if reduced || elapsed_ms >= self.duration_ms {
            frame.field_opacity = [1.0; 4];
            return frame;
        }
        if elapsed_ms <= 0.0 {
            return frame;
        }
        for (i, opacity) in frame.field_opacity.iter_mut().enumerate() {
            let t = ((elapsed_ms - self.drops[0].fall_ms - 90.0 - i as f64 * 78.0) / 260.0)
                .clamp(0.0, 1.0);
            *opacity = t * t * (3.0 - 2.0 * t);
        }
        for (i, drop) in self.drops.iter().take(self.count as usize).enumerate() {
            let impact = drop.start_ms + drop.fall_ms;
            if elapsed_ms < drop.start_ms || elapsed_ms >= impact + drop.decay_ms {
                continue;
            }
            let first = i == 0;
            if elapsed_ms < impact {
                let t = (elapsed_ms - drop.start_ms) / drop.fall_ms;
                let top = if first { -30.0 } else { 12.0 };
                let x = drop.offset + self.drift * (1.0 - t);
                let y = top + (drop.depth - top) * t * t;
                frame.push(if first {
                    RainShape {
                        kind: ShapeKind::Bead,
                        x: x - 4.0,
                        y: y - 10.0,
                        a: 8.0,
                        b: 10.0,
                        opacity: 1.0,
                        ..RainShape::default()
                    }
                } else {
                    RainShape {
                        kind: ShapeKind::Line,
                        x: x + 0.45,
                        y: y - 2.8,
                        a: x,
                        b: y,
                        opacity: 0.55 * (t * 5.0).min(1.0),
                        stroke: 0.95,
                        ..RainShape::default()
                    }
                });
            } else {
                let age = (elapsed_ms - impact) / drop.decay_ms;
                let radius = 1.0 + drop.radius * (1.0 - (1.0 - age).powi(2));
                let alpha = (1.0 - age).powf(1.35);
                let ring = RainShape {
                    kind: ShapeKind::Ellipse,
                    x: drop.offset,
                    y: drop.depth,
                    a: radius,
                    b: 0.6 + radius * 0.18,
                    opacity: alpha * if first { 0.65 } else { 0.33 },
                    stroke: if first { 1.0 } else { 0.8 },
                    ..RainShape::default()
                };
                frame.push(ring);
                if first {
                    frame.push(RainShape {
                        kind: ShapeKind::Arc,
                        opacity: alpha * 0.34,
                        start_deg: 32.0,
                        sweep_deg: 106.0,
                        ..ring
                    });
                }
            }
        }
        frame
    }
}

impl RainShower {
    pub(super) fn draw(&self, t: f64, active: bool, scenery: &mut super::Canvas) -> [f64; 4] {
        use crate::overlay::frame::Ink;
        let f = self.frame(if active { t * 1000. } else { self.duration_ms }, false);
        for s in &f.shapes[..f.count as usize] {
            match s.kind {
                ShapeKind::Bead => scenery.symbol(0, s.x, s.y, s.a, s.b),
                ShapeKind::Line => {
                    scenery.begin();
                    scenery.mov(s.x, s.y);
                    scenery.to(s.a, s.b);
                    scenery.stroke(Ink::White, s.opacity, s.stroke, false);
                }
                ShapeKind::Ellipse => {
                    scenery.ellipse(s.x - s.a, s.y - s.b, 2. * s.a, 2. * s.b);
                    scenery.stroke(Ink::White, s.opacity, s.stroke, false);
                }
                ShapeKind::Arc => {
                    scenery.unit_arc(s.start_deg, s.sweep_deg);
                    // Transform the path before stroking to keep the pen width constant.
                    scenery.transform_arc(s.x, s.y, s.a, s.b);
                    scenery.stroke(Ink::White, s.opacity, s.stroke, false);
                }
            }
        }
        f.field_opacity
    }
}
