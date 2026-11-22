#![cfg(feature = "overlay")]

use avesd_core::rain::{RainShower, ShapeKind};
use serde_json::{Value, json};

#[test]
fn rain_matches_shared_keyframes() {
    let fixture: Value = serde_json::from_str(include_str!("fixtures/overlay/rain.json")).unwrap();
    let shower = RainShower::new(fixture["seed"].as_u64().unwrap());
    let rounded = |v: f64| (v * 1e6).round() / 1e6;

    for expected in fixture["frames"].as_array().unwrap() {
        let ms = expected["elapsed_ms"].as_f64().unwrap();
        let frame = shower.frame(ms, expected["reduce_motion"].as_bool().unwrap());
        assert_eq!(
            json!(frame.field_opacity.map(rounded)),
            expected["field_opacity"],
            "at {ms} ms"
        );
        let shapes: Vec<_> = frame.shapes[..frame.count as usize]
            .iter()
            .map(|s| {
                let xy = [rounded(s.x), rounded(s.y)];
                let ab = [rounded(s.a), rounded(s.b)];
                let mut shape = match s.kind {
                    ShapeKind::Bead => json!({"kind": "bead", "origin": xy, "size": ab}),
                    ShapeKind::Line => json!({"kind": "line", "from": xy, "to": ab}),
                    ShapeKind::Ellipse => json!({"kind": "ellipse", "center": xy, "radii": ab}),
                    ShapeKind::Arc => json!({"kind": "arc", "center": xy, "radii": ab,
                                         "start_deg": s.start_deg, "sweep_deg": s.sweep_deg}),
                };
                shape["opacity"] = json!(rounded(s.opacity));
                if s.kind != ShapeKind::Bead {
                    shape["stroke_width"] = json!(s.stroke);
                }
                shape
            })
            .collect();
        assert_eq!(json!(shapes), expected["shapes"], "at {ms} ms");
    }
}
