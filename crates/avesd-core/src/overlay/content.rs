use avesd_events::{Event, Payload, Place, rain::Intensity, turning_tide::Turn};
use chrono_tz::Tz;
use serde::Serialize;
use std::borrow::Cow;

#[derive(Default, Serialize)]
pub struct Content<'a> {
    pub icon: &'static str,
    pub headline: &'a str,
    pub route_destination: Option<&'a str>,
    pub secondary: &'a str,
    pub trailing: Cow<'a, str>,
    pub title: &'a str,
    pub caption: &'a str,
    pub rows: Vec<(&'static str, Cow<'a, str>)>,
    pub accessibility: String,
    pub airline_code: Option<&'a str>,
    pub airline_mark: Option<&'a str>,
}

fn intensity(i: Intensity) -> &'static str {
    match i {
        Intensity::None => "no",
        Intensity::Light => "light",
        Intensity::Moderate => "moderate",
        Intensity::Heavy => "heavy",
    }
}
impl<'a> Content<'a> {
    pub fn new(event: &'a Event, preview: bool) -> Option<Self> {
        use Payload::*;
        let icon = match event.payload {
            Flyover(_) => "airline",
            Rain(_) => "rain",
            _ => "artwork",
        };
        let mut content = Self {
            icon,
            ..Self::default()
        };
        if let Flyover(f) = &event.payload {
            content.headline = f
                .origin
                .as_deref()
                .or(f.callsign.as_deref())
                .unwrap_or(&f.aircraft_id);
            content.route_destination = f.destination.as_deref();
            content.secondary = f
                .callsign
                .as_deref()
                .filter(|callsign| *callsign != content.headline)
                .unwrap_or_default();
            content.trailing = f.aircraft_type.as_deref().unwrap_or_default().into();
            content.airline_code = Some(f.airline_code.as_deref().unwrap_or("✈"));
            content.airline_mark = f.airline_mark.as_deref();
            content.title = f.airline_name.as_deref().unwrap_or(&f.aircraft_id);
            content.caption = f.flight_number.as_deref().unwrap_or_default();
            for (key, value) in [
                ("From", f.origin_name.as_deref()),
                ("To", f.destination_name.as_deref()),
                ("Aircraft", f.model.as_deref()),
            ] {
                if let Some(value) = value {
                    content.rows.push((key, value.into()));
                }
            }
            let description = &mut content.accessibility;
            description.push_str(content.title);
            if let Some(callsign) = &f.callsign {
                description.push_str(", ");
                description.push_str(callsign);
            }
            if let (Some(from), Some(to)) = (&f.origin_name, &f.destination_name) {
                description.push_str(", ");
                description.push_str(from);
                description.push_str(" to ");
                description.push_str(to);
            }
            if let Some(model) = &f.model {
                description.push_str(", ");
                description.push_str(model);
            }
            return Some(content);
        }
        let (place, change, detail): (&Place, &str, String) = match &event.payload {
            Note(note) => {
                let summary = note.summary.trim();
                if summary.is_empty() {
                    return None;
                }
                content.headline = summary;
                content.title = summary;
                content.accessibility = summary.to_owned();
                if let Some(detail) = note
                    .detail
                    .as_deref()
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                {
                    content.rows.push(("Detail", detail.into()));
                    content.accessibility.push_str(". ");
                    content.accessibility.push_str(detail);
                }
                return Some(content);
            }
            Rain(r) if r.previous_intensity.is_none() && r.current_intensity.is_none() => {
                content.headline = r.place.local_name.as_deref().unwrap_or(&r.place.place);
                content.secondary = "正在下雨";
                content.title = &r.place.place;
                content.caption = if preview { "Sample" } else { "" };
                content.rows.push(("Event", "Rain".into()));
                content.accessibility = format!(
                    "Rain in {}.{}",
                    r.place.place,
                    if preview { " Sample event." } else { "" }
                );
                return Some(content);
            }
            Rain(r) => {
                let change = match r.current_intensity.cmp(&r.previous_intensity) {
                    std::cmp::Ordering::Greater => "雨势转强",
                    std::cmp::Ordering::Less => "雨势减弱",
                    std::cmp::Ordering::Equal => "雨势平稳",
                };
                let mut text = format!(
                    "{} to {} rain",
                    intensity(r.previous_intensity?),
                    intensity(r.current_intensity?)
                );
                text[..1].make_ascii_uppercase();
                (&r.place, change, text)
            }
            Sunrise(s) => {
                let n = s.minutes_later_than_yesterday;
                let detail = match n {
                    0 => "Sunrise at the same time as yesterday".into(),
                    1 => "Sunrise one minute later than yesterday".into(),
                    _ => format!(
                        "Sunrise {} minute{} {} than yesterday",
                        n.unsigned_abs(),
                        if n.unsigned_abs() == 1 { "" } else { "s" },
                        if n > 0 { "later" } else { "earlier" }
                    ),
                };
                (&s.place, "日出", detail)
            }
            BridgeLift(b) => (
                &b.place,
                "桥面开启",
                format!("Bridge opening for {}", b.reason),
            ),
            TurningTide(t) => match t.turn {
                Turn::HighToFalling => (
                    &t.place,
                    "高潮转落",
                    "Water level falling after high tide".into(),
                ),
                Turn::LowToRising => (
                    &t.place,
                    "低潮转涨",
                    "Water level rising after low tide".into(),
                ),
            },
            LastTrain(t) => (
                &t.place,
                "末班车驶离",
                format!(
                    "Last {} train towards {}",
                    t.line,
                    t.destination_name.as_deref().unwrap_or(&t.destination)
                ),
            ),
            Flyover(_) => unreachable!(),
        };
        let zone = place.time_zone.parse::<Tz>().ok()?;
        let local = event.occurred_at.with_timezone(&zone);
        content.headline = place.local_name.as_deref().unwrap_or(&place.place);
        content.secondary = change;
        content.trailing = local.format("%H:%M").to_string().into();
        content.title = &place.place;
        if preview {
            content.caption = "Sample";
        }
        let time = local.format("%H:%M %Z").to_string();
        let (description, sample_suffix) = if let Rain(r) = &event.payload {
            let description = match r.current_intensity.cmp(&r.previous_intensity) {
                std::cmp::Ordering::Greater => "Rain intensifying",
                std::cmp::Ordering::Less => "Rain easing",
                std::cmp::Ordering::Equal => "Rain steady",
            };
            (description, " Sample observation.")
        } else {
            (detail.as_str(), " Sample event.")
        };
        content.accessibility = format!(
            "{}. {} at {}.{}",
            place.place,
            description,
            time,
            if preview { sample_suffix } else { "" }
        );
        let detail_label = if matches!(event.payload, Rain(_)) {
            "Precipitation"
        } else {
            "Event"
        };
        let clock_label = if place.time_zone == "UTC" {
            "UTC time"
        } else {
            "Local time"
        };
        content.rows = vec![(clock_label, time.into()), (detail_label, detail.into())];
        Some(content)
    }
}
