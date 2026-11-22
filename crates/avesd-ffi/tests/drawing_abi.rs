use avesd_core::overlay::frame::{Ink, Op};
use std::collections::BTreeMap;

fn header_codes(prefix: &str) -> BTreeMap<&'static str, u32> {
    let mut values = BTreeMap::new();
    for entry in include_str!("../include/avesd.h")
        .lines()
        .filter_map(|line| line.trim().strip_prefix(prefix))
    {
        let (name, value) = entry
            .trim_end_matches(',')
            .split_once('=')
            .expect("public drawing codes require explicit values");
        assert!(
            values
                .insert(name.trim(), value.trim().parse().unwrap())
                .is_none()
        );
    }
    values
}

macro_rules! check_codes {
    ($ty:ident, $prefix:literal, {$($variant:ident => $name:literal),+ $(,)?}) => {{
        // Exhaustiveness makes a new Rust variant require a C spelling here.
        let name = |value: $ty| match value { $($ty::$variant => $name),+ };
        let rust = BTreeMap::from([$( (name($ty::$variant), $ty::$variant as u32) ),+]);
        assert_eq!(rust, header_codes($prefix));
    }};
}

#[test]
fn native_drawing_codes_match_the_public_header() {
    check_codes!(Op, "AVESD_OP_", {
        Begin => "BEGIN",
        Move => "MOVE",
        LineTo => "LINE_TO",
        Quad => "QUAD",
        Close => "CLOSE",
        Rect => "RECT",
        RoundRect => "ROUND_RECT",
        Ellipse => "ELLIPSE",
        Arc => "ARC",
        Fill => "FILL",
        Stroke => "STROKE",
        Clip => "CLIP",
        Save => "SAVE",
        Restore => "RESTORE",
        Translate => "TRANSLATE",
        Rotate => "ROTATE",
        Scale => "SCALE",
        Opacity => "OPACITY",
        BeginLayer => "BEGIN_LAYER",
        EndLayer => "END_LAYER",
        Gradient => "GRADIENT",
        Stop => "STOP",
        FillGradient => "FILL_GRADIENT",
        StrokeGradient => "STROKE_GRADIENT",
        Glyph => "GLYPH",
        Symbol => "SYMBOL",
        Shadow => "SHADOW",
        TransformArc => "TRANSFORM_ARC",
    });
    check_codes!(Ink, "AVESD_INK_", {
        White => "WHITE",
        Ivory => "IVORY",
        Silver => "SILVER",
        Brass => "BRASS",
        Slate => "SLATE",
        Brick => "BRICK",
        Black => "BLACK",
        Clear => "CLEAR",
    });
}
