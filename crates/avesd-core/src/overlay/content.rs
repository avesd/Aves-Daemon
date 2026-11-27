use avesd_events::{Event, Payload, Place, flyover::Flyover, rain::Intensity, turning_tide::Turn};
use chrono_tz::{OffsetComponents, Tz};
use serde::Serialize;
use std::cmp::Ordering;

#[derive(Serialize)]
pub struct Content<'a> {
    presentation: Presentation<'a>,
    preview: bool,
    #[serde(skip)]
    pub timetable: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
enum Presentation<'a> {
    Flyover {
        flight: &'a Flyover,
    },
    Note {
        summary: &'a str,
        detail: Option<&'a str>,
    },
    Observation {
        place: &'a Place,
        clock: Option<Clock>,
        change: Change<'a>,
    },
}

#[derive(Serialize)]
struct Clock {
    timestamp: i64,
    offset_seconds: i64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
enum Change<'a> {
    Raining {},
    Rain {
        trend: Trend,
        previous: Intensity,
        current: Intensity,
    },
    SunriseSame {},
    SunriseEarlier {
        minutes: u32,
    },
    SunriseLater {
        minutes: u32,
    },
    BridgeLift {
        reason: &'a str,
    },
    HighToFalling {},
    LowToRising {},
    LastTrain {
        line: &'a str,
        destination: &'a str,
    },
}

#[derive(Serialize)]
#[serde(rename_all = "lowercase")]
enum Trend {
    Intensifying,
    Easing,
    Steady,
}

impl<'a> Content<'a> {
    pub fn new(event: &'a Event, preview: bool) -> Option<Self> {
        let mut timetable = String::new();
        let presentation = match &event.payload {
            Payload::Flyover(flight) => Presentation::Flyover { flight },
            Payload::Note(note) => {
                let summary = note.summary.trim();
                if summary.is_empty() {
                    return None;
                }
                Presentation::Note {
                    summary,
                    detail: note
                        .detail
                        .as_deref()
                        .map(str::trim)
                        .filter(|s| !s.is_empty()),
                }
            }
            payload => {
                let (place, change) = match payload {
                    Payload::Rain(r) => {
                        let change = match (r.previous_intensity, r.current_intensity) {
                            (None, None) => Change::Raining {},
                            (Some(previous), Some(current)) => {
                                let trend = match current.cmp(&previous) {
                                    Ordering::Greater => Trend::Intensifying,
                                    Ordering::Less => Trend::Easing,
                                    Ordering::Equal => Trend::Steady,
                                };
                                Change::Rain {
                                    trend,
                                    previous,
                                    current,
                                }
                            }
                            _ => return None,
                        };
                        (&r.place, change)
                    }
                    Payload::Sunrise(s) => {
                        let delta = s.minutes_later_than_yesterday;
                        let minutes = delta.unsigned_abs();
                        let change = match delta.cmp(&0) {
                            Ordering::Equal => Change::SunriseSame {},
                            Ordering::Less => Change::SunriseEarlier { minutes },
                            Ordering::Greater => Change::SunriseLater { minutes },
                        };
                        (&s.place, change)
                    }
                    Payload::BridgeLift(b) => (&b.place, Change::BridgeLift { reason: &b.reason }),
                    Payload::TurningTide(t) => (
                        &t.place,
                        match t.turn {
                            Turn::HighToFalling => Change::HighToFalling {},
                            Turn::LowToRising => Change::LowToRising {},
                        },
                    ),
                    Payload::LastTrain(t) => (
                        &t.place,
                        Change::LastTrain {
                            line: &t.line,
                            destination: t.destination_name.as_deref().unwrap_or(&t.destination),
                        },
                    ),
                    Payload::Flyover(_) | Payload::Note(_) => unreachable!(),
                };
                let clock = if matches!(change, Change::Raining {}) {
                    None
                } else {
                    let zone = place.time_zone.parse::<Tz>().ok()?;
                    let local = event.occurred_at.with_timezone(&zone);
                    if matches!(change, Change::LastTrain { .. }) {
                        timetable = local.format("%H:%M").to_string();
                    }
                    let offset = local.offset();
                    Some(Clock {
                        timestamp: local.timestamp(),
                        offset_seconds: (offset.base_utc_offset() + offset.dst_offset())
                            .num_seconds(),
                    })
                };
                Presentation::Observation {
                    place,
                    clock,
                    change,
                }
            }
        };
        Some(Self {
            presentation,
            preview,
            timetable,
        })
    }
}
