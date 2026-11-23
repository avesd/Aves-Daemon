use avesd_core::overlay::{
    content::Content,
    effects::Layout,
    frame::Command,
    playback::{FrameChanges, Panel, Playback},
};
use avesd_events::Event;
use std::ffi::{CString, c_char};

pub struct Session {
    playback: Playback,
    content: CString,
}
#[repr(C)]
pub struct Options {
    seed: u64,
    hold_ms: f64,
    width: f64,
    anchor_x: f64,
    reduced: bool,
}
#[repr(C)]
pub struct Frame {
    panel: Panel,
    icon: *const Command,
    icon_count: usize,
    scenery: *const Command,
    scenery_count: usize,
}
fn create(data: &[u8], o: Options, preview: bool) -> Option<Box<Session>> {
    let event: Event = serde_json::from_slice(data).ok()?;
    if event.id.trim().is_empty()
        || !o.hold_ms.is_finite()
        || o.hold_ms <= 0.
        || !o.width.is_finite()
        || !o.anchor_x.is_finite()
        || !(0.0..o.width).contains(&o.anchor_x)
    {
        return None;
    }
    let content = Content::new(&event, preview)?;
    let playback = Playback::new(
        &event,
        &content,
        o.seed,
        o.reduced,
        o.hold_ms,
        Layout {
            width: o.width,
            anchor_x: o.anchor_x,
        },
    );
    Some(Box::new(Session {
        playback,
        content: CString::new(serde_json::to_vec(&content).ok()?).ok()?,
    }))
}
/// Creates a session from one UTF-8 JSON event record.
///
/// # Safety
/// A non-null `data` must point to a single allocation containing at least
/// `len` initialized bytes, readable and unmodified for the duration of this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn avesd_overlay_create(
    data: *const u8,
    len: usize,
    o: Options,
) -> Option<Box<Session>> {
    if data.is_null() || len > isize::MAX as usize {
        return None;
    }
    create(unsafe { std::slice::from_raw_parts(data, len) }, o, false)
}
#[unsafe(no_mangle)]
pub extern "C" fn avesd_overlay_preview(kind: u32, o: Options) -> Option<Box<Session>> {
    let data: &[u8] = match kind {
        0 => include_bytes!("../../avesd-events/fixtures/flyover.json"),
        1 => include_bytes!("../../avesd-events/fixtures/rain.json"),
        2 => include_bytes!("../../avesd-events/fixtures/sunrise.json"),
        3 => include_bytes!("../../avesd-events/fixtures/bridge_lift.json"),
        4 => include_bytes!("../../avesd-events/fixtures/turning_tide.json"),
        5 => include_bytes!("../../avesd-events/fixtures/last_train.json"),
        _ => return None,
    };
    create(data, o, true)
}
#[unsafe(no_mangle)]
pub extern "C" fn avesd_overlay_destroy(_session: Option<Box<Session>>) {}
#[unsafe(no_mangle)]
pub extern "C" fn avesd_overlay_content(session: &Session) -> *const c_char {
    session.content.as_ptr()
}
#[unsafe(no_mangle)]
pub extern "C" fn avesd_overlay_advance(session: &mut Session, ms: f64, inside: bool) -> bool {
    session.playback.advance(ms, inside)
}
#[unsafe(no_mangle)]
pub extern "C" fn avesd_overlay_advance_changes(
    session: &mut Session,
    ms: f64,
    inside: bool,
) -> FrameChanges {
    session.playback.advance_changes(ms, inside)
}
#[unsafe(no_mangle)]
pub extern "C" fn avesd_overlay_frame(session: &Session) -> Frame {
    let p = &session.playback;
    Frame {
        panel: p.panel,
        icon: p.icon.0.as_ptr(),
        icon_count: p.icon.0.len(),
        scenery: p.scenery.0.as_ptr(),
        scenery_count: p.scenery.0.len(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{Value, json};

    #[test]
    fn record_ingress_skips_an_unknown_kind_and_formats_live_local_time() {
        let mut record: Value =
            serde_json::from_slice(include_bytes!("../../avesd-events/fixtures/rain.json"))
                .unwrap();
        record["occurred_at"] = json!("2026-07-10T09:42:00Z");
        record["data"]["time_zone"] = json!("Europe/London");
        record["data"]["future_field"] = json!(42);
        let options = || Options {
            seed: 42,
            hold_ms: 3000.,
            width: 368.,
            anchor_x: 65.,
            reduced: false,
        };
        let mut legacy_rain = record.clone();
        legacy_rain["data"]["previous_intensity"] = json!("light");
        legacy_rain["data"]["current_intensity"] = json!("heavy");
        let mut unknown = record.clone();
        unknown["kind"] = json!("future_event");
        for (data, expected) in [
            (unknown, None),
            (legacy_rain, Some(("雨势转强", "10:42"))),
            (record, Some(("正在下雨", ""))),
        ] {
            let bytes = serde_json::to_vec(&data).unwrap();
            let session = unsafe { avesd_overlay_create(bytes.as_ptr(), bytes.len(), options()) };
            assert_eq!(session.is_some(), expected.is_some());
            if let Some(session) = session {
                let content: Value = serde_json::from_slice(session.content.as_bytes()).unwrap();
                let (message, trailing) = expected.unwrap();
                assert_eq!(content["secondary"], message);
                assert_eq!(content["trailing"], trailing);
                assert_eq!(content["caption"], "");
                assert!(
                    !content["accessibility"]
                        .as_str()
                        .unwrap()
                        .contains("Sample")
                );
            }
        }
    }
}
