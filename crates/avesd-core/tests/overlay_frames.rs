#![cfg(feature = "overlay")]

use avesd_core::overlay::{content::Content, effects::Layout, frame::Op, playback::Playback};
use avesd_events::Event;
use serde_json::{Value, json};

fn session(bytes: &str, seed: u64, reduced: bool) -> Playback {
    let event: Event = serde_json::from_str(bytes).unwrap();
    let content = Content::new(&event, true).unwrap();
    Playback::new(
        &event,
        &content,
        seed,
        reduced,
        3000.,
        Layout {
            width: 368.,
            anchor_x: 65.,
        },
    )
}

macro_rules! case {
    ($kind:literal) => {
        (
            $kind,
            include_str!(concat!("../../avesd-events/fixtures/", $kind, ".json")),
            include_str!(concat!("fixtures/overlay/", $kind, ".json")),
        )
    };
}

#[test]
fn shared_effects_keep_their_gesture_and_resting_icon() {
    for (kind, event, fixture) in [
        case!("flyover"),
        case!("sunrise"),
        case!("bridge_lift"),
        case!("turning_tide"),
        case!("last_train"),
    ] {
        let key: Value = serde_json::from_str(fixture).unwrap();
        let seed = key["seed"].as_u64().unwrap();
        let mut s = session(event, seed, false);
        s.advance(key["elapsed_ms"].as_f64().unwrap(), false);
        let mut commands = s.scenery.0.iter();
        let rounded = |v: f64| (v * 1e6).round() / 1e6;
        let landmark = match kind {
            "flyover" => {
                let plane = commands.find(|c| c.op == Op::Symbol).unwrap();
                json!([
                    rounded(plane.x),
                    rounded(plane.y),
                    rounded(s.panel.reveal_edge)
                ])
            }
            "sunrise" => {
                let tip = commands.rfind(|c| c.op == Op::Gradient).unwrap();
                json!([rounded(tip.a), rounded(tip.b)])
            }
            "bridge_lift" => json!([rounded(commands.find(|c| c.op == Op::Rotate).unwrap().x)]),
            "turning_tide" => {
                let boat = commands.find(|c| c.op == Op::Translate).unwrap();
                json!([
                    rounded(boat.x),
                    rounded(boat.y),
                    rounded(commands.find(|c| c.op == Op::Rotate).unwrap().x)
                ])
            }
            "last_train" => json!(
                s.icon
                    .0
                    .iter()
                    .filter(|c| c.op == Op::Glyph)
                    .map(|c| char::from_u32(c.tag).unwrap())
                    .collect::<Vec<_>>()
            ),
            _ => unreachable!(),
        };
        assert_eq!(landmark, key["landmark"], "{kind}");
        let reduced = session(event, seed, true);
        assert_eq!(reduced.panel.fields, [1.; 4]);
        assert!(reduced.scenery.0.is_empty());
        s.advance(7700., false);
        assert_eq!(s.icon.0, reduced.icon.0, "resting {kind}");
    }
}

#[test]
fn hover_holds_reopens_and_resumes_dismissal() {
    let event = include_str!("../../avesd-events/fixtures/flyover.json");
    for reduced in [false, true] {
        let mut s = session(event, 42, reduced);
        let settled = if reduced { 0. } else { 2350. };
        s.advance(settled, false);
        s.advance(settled + 100., true);
        assert_eq!(s.panel.expansion, 0.);
        s.advance(settled + 630., true);
        assert_eq!(s.panel.expansion, 1.);
        s.advance(settled + 20_000., true);
        assert!(s.panel.alive);
        s.advance(settled + 20_400., false);
        assert_eq!(s.panel.expansion, 0.);
        s.advance(settled + 21_100., true);
        assert_eq!(s.panel.expansion, 1.);
        s.advance(settled + 25_000., false);
        assert!(!s.panel.alive);
    }
}

#[test]
fn layer_changes_match_command_snapshots_through_settling_and_hover() {
    for event in [
        include_str!("../../avesd-events/fixtures/rain.json"),
        include_str!("../../avesd-events/fixtures/flyover.json"),
        include_str!("../../avesd-events/fixtures/sunrise.json"),
        include_str!("../../avesd-events/fixtures/bridge_lift.json"),
        include_str!("../../avesd-events/fixtures/turning_tide.json"),
        include_str!("../../avesd-events/fixtures/last_train.json"),
    ] {
        let mut playback = session(event, 42, false);
        for ms in (0..9000).step_by(40) {
            let (panel, icon, scenery) = (
                playback.panel,
                playback.icon.0.clone(),
                playback.scenery.0.clone(),
            );
            let changes = playback.advance_changes(f64::from(ms), (4000..8200).contains(&ms));
            assert_eq!(changes.panel, playback.panel != panel);
            assert_eq!(changes.icon, playback.icon.0 != icon);
            assert_eq!(changes.scenery, playback.scenery.0 != scenery);
        }
        assert!(playback.scenery.0.is_empty());
    }
}

#[test]
fn flyover_shows_the_callsign_once_with_or_without_a_route() {
    let mut record: Value =
        serde_json::from_str(include_str!("../../avesd-events/fixtures/flyover.json")).unwrap();
    let check = |record: &Value, headline: &str, secondary: &str| {
        let event = serde_json::from_value(record.clone()).unwrap();
        let view = Content::new(&event, false).unwrap();
        assert_eq!((view.headline, view.secondary), (headline, secondary));
    };
    let flight = &record["data"];
    let callsign = flight["callsign"].as_str().unwrap().to_owned();
    check(&record, flight["origin"].as_str().unwrap(), &callsign);
    record["data"].as_object_mut().unwrap().remove("origin");
    check(&record, &callsign, "");
}
