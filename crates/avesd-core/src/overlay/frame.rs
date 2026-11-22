//! Drawing coordinates use logical pixels relative to the center of the icon.
#[derive(Clone, Copy, Debug, PartialEq)]
#[repr(u32)]
pub enum Op {
    Begin = 0,
    Move = 1,
    LineTo = 2,
    Quad = 3,
    Close = 4,
    Rect = 5,
    RoundRect = 6,
    Ellipse = 7,
    Arc = 8,
    Fill = 9,
    Stroke = 10,
    Clip = 11,
    Save = 12,
    Restore = 13,
    Translate = 14,
    Rotate = 15,
    Scale = 16,
    Opacity = 17,
    BeginLayer = 18,
    EndLayer = 19,
    Gradient = 20,
    Stop = 21,
    FillGradient = 22,
    StrokeGradient = 23,
    Glyph = 24,
    Symbol = 25,
    Shadow = 26,
    TransformArc = 27,
}

#[derive(Clone, Copy, Debug)]
#[repr(u32)]
pub enum Ink {
    White = 0,
    Ivory = 1,
    Silver = 2,
    Brass = 3,
    Slate = 4,
    Brick = 5,
    Black = 6,
    Clear = 7,
}

#[derive(Clone, Copy, Debug, PartialEq)]
#[repr(C)]
pub struct Command {
    pub op: Op,
    pub tag: u32,
    pub x: f64,
    pub y: f64,
    pub a: f64,
    pub b: f64,
}

#[derive(Default)]
pub struct Canvas(pub Vec<Command>);

impl Canvas {
    pub(super) fn replace_if_changed(&mut self, sampled: &mut Self) -> bool {
        if self.0 == sampled.0 {
            return false;
        }
        std::mem::swap(self, sampled);
        true
    }

    fn emit(&mut self, op: Op, tag: u32, [x, y, a, b]: [f64; 4]) {
        self.0.push(Command {
            op,
            tag,
            x,
            y,
            a,
            b,
        });
    }
    fn simple(&mut self, op: Op) {
        self.emit(op, 0, [0.; 4]);
    }
    pub fn begin(&mut self) {
        self.simple(Op::Begin);
    }
    pub fn mov(&mut self, x: f64, y: f64) {
        self.emit(Op::Move, 0, [x, y, 0., 0.]);
    }
    pub fn to(&mut self, x: f64, y: f64) {
        self.emit(Op::LineTo, 0, [x, y, 0., 0.]);
    }
    pub fn quad(&mut self, x: f64, y: f64, cx: f64, cy: f64) {
        self.emit(Op::Quad, 0, [x, y, cx, cy]);
    }
    pub fn close(&mut self) {
        self.simple(Op::Close);
    }
    pub fn rect(&mut self, x: f64, y: f64, w: f64, h: f64) {
        self.emit(Op::Rect, 0, [x, y, w, h]);
    }
    pub fn round_rect(&mut self, x: f64, y: f64, w: f64, h: f64, r: f64) {
        self.emit(Op::RoundRect, (r * 1000.).round() as u32, [x, y, w, h]);
    }
    pub fn ellipse(&mut self, x: f64, y: f64, w: f64, h: f64) {
        self.emit(Op::Ellipse, 0, [x, y, w, h]);
    }
    pub fn unit_arc(&mut self, start: f64, sweep: f64) {
        self.emit(Op::Arc, 0, [start, sweep, 0., 0.]);
    }
    pub fn fill(&mut self, ink: Ink, alpha: f64) {
        self.emit(Op::Fill, ink as u32, [alpha, 0., 0., 0.]);
    }
    pub fn stroke(&mut self, ink: Ink, alpha: f64, width: f64, round: bool) {
        self.emit(
            Op::Stroke,
            ink as u32,
            [alpha, width, if round { 1. } else { 0. }, 0.],
        );
    }
    pub fn line(&mut self, p: (f64, f64), q: (f64, f64), ink: Ink, alpha: f64, width: f64) {
        self.begin();
        self.mov(p.0, p.1);
        self.to(q.0, q.1);
        self.stroke(ink, alpha, width, true);
    }
    pub fn polygon(&mut self, pts: &[(f64, f64)]) {
        self.begin();
        if let Some((p, rest)) = pts.split_first() {
            self.mov(p.0, p.1);
            for &(x, y) in rest {
                self.to(x, y);
            }
            self.close();
        }
    }
    pub fn face(&mut self, pts: &[(f64, f64)], fill: Ink, alpha: f64, outline: Option<Ink>) {
        self.polygon(pts);
        self.fill(fill, alpha);
        if let Some(ink) = outline {
            self.stroke(ink, 1., 0.7, false);
        }
    }
    pub fn transform_arc(&mut self, x: f64, y: f64, rx: f64, ry: f64) {
        self.emit(Op::TransformArc, 0, [x, y, rx, ry]);
    }
    pub fn clip(&mut self) {
        self.simple(Op::Clip);
    }
    pub fn save(&mut self) {
        self.simple(Op::Save);
    }
    pub fn restore(&mut self) {
        self.simple(Op::Restore);
    }
    pub fn translate(&mut self, x: f64, y: f64) {
        self.emit(Op::Translate, 0, [x, y, 0., 0.]);
    }
    pub fn rotate(&mut self, r: f64) {
        self.emit(Op::Rotate, 0, [r, 0., 0., 0.]);
    }
    pub fn scale(&mut self, x: f64, y: f64) {
        self.emit(Op::Scale, 0, [x, y, 0., 0.]);
    }
    pub fn opacity(&mut self, alpha: f64) {
        self.emit(Op::Opacity, 0, [alpha, 0., 0., 0.]);
    }
    pub fn layer(&mut self) {
        self.simple(Op::BeginLayer);
    }
    pub fn end_layer(&mut self) {
        self.simple(Op::EndLayer);
    }
    pub fn gradient(&mut self, p: (f64, f64), q: (f64, f64), stops: &[(Ink, f64)]) {
        self.emit(Op::Gradient, 0, [p.0, p.1, q.0, q.1]);
        for &(ink, alpha) in stops {
            self.emit(Op::Stop, ink as u32, [alpha, 0., 0., 0.]);
        }
    }
    pub fn fill_gradient(&mut self) {
        self.simple(Op::FillGradient);
    }
    pub fn stroke_gradient(&mut self, w: f64) {
        self.emit(Op::StrokeGradient, 0, [w, 0., 0., 0.]);
    }
    pub fn glyph(&mut self, ch: char, font: f64, ink: Ink) {
        self.emit(Op::Glyph, ch as u32, [font, ink as u32 as f64, 0., 0.]);
    }
    pub fn symbol(&mut self, symbol: u32, x: f64, y: f64, w: f64, h: f64) {
        self.emit(Op::Symbol, symbol, [x, y, w, h]);
    }
    pub fn shadow(&mut self, alpha: f64, radius: f64, y: f64) {
        self.emit(Op::Shadow, 0, [alpha, radius, y, 0.]);
    }
}
pub fn eased(t: f64, from: f64, to: f64) -> f64 {
    let v = ((t - from) / (to - from)).clamp(0., 1.);
    v * v * (3. - 2. * v)
}
