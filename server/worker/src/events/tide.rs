use avesd_events::{
    Event, Payload, Place,
    turning_tide::{Turn, TurningTide},
};
use chrono::{DateTime, TimeDelta, Utc};
use futures_util::{future::LocalBoxFuture, try_join};

use super::{Candidate, EventProvider, EventResult, Query, Scope};
use crate::sources::{
    noaa,
    water_level::{Extremum, PredictedTurn, Station, WaterLevel},
};

fn turns(
    station: &Station,
    readings: &[WaterLevel],
    predictions: &[PredictedTurn],
    now: DateTime<Utc>,
) -> Vec<Candidate> {
    let mut candidates = Vec::new();
    for prediction in predictions {
        let (sign, code, turn) = match prediction.kind {
            Extremum::High => (1., "H", Turn::HighToFalling),
            Extremum::Low => (-1., "L", Turn::LowToRising),
        };
        // Confirm a local extremum with two successive six-minute readings on both sides.
        let best = readings
            .windows(5)
            .filter(|w| {
                let age = now - w[4].at;
                if !(TimeDelta::zero()..TimeDelta::minutes(15)).contains(&age)
                    || (w[2].at - prediction.at).abs() > TimeDelta::hours(1)
                    || !w
                        .windows(2)
                        .all(|p| p[1].at - p[0].at == TimeDelta::minutes(6))
                {
                    return false;
                }
                let peak = w[2].metres;
                (peak - w[0].metres) * sign >= 0.02
                    && (peak - w[4].metres) * sign >= 0.02
                    && (w[1].metres - w[0].metres) * sign >= 0.
                    && (peak - w[1].metres) * sign >= 0.
                    && (peak - w[3].metres) * sign > 0.
                    && (w[3].metres - w[4].metres) * sign > 0.
            })
            .min_by(|a, b| {
                (a[2].at - prediction.at)
                    .abs()
                    .cmp(&(b[2].at - prediction.at).abs())
                    .then_with(|| (b[2].metres * sign).total_cmp(&(a[2].metres * sign)))
            });
        let Some(window) = best else { continue };
        candidates.push(Candidate {
            expires_at: window[4].at + TimeDelta::minutes(15),
            event: Event {
                id: format!(
                    "tide:noaa:{}:{code}:{}",
                    station.id,
                    prediction.at.timestamp()
                ),
                occurred_at: window[2].at.fixed_offset(),
                payload: Payload::TurningTide(TurningTide {
                    place: Place {
                        place: format!("{} (UTC)", station.name),
                        local_name: None,
                        time_zone: "UTC".into(),
                    },
                    turn,
                }),
            },
        });
    }
    candidates
}

pub struct Tides;

impl EventProvider for Tides {
    fn events<'a>(&self, query: Query<'a>, scope: Scope<'a>) -> LocalBoxFuture<'a, EventResult> {
        Box::pin(async move {
            let Scope::Nearby { region, .. } = scope else {
                return Ok(Vec::new());
            };
            let stations = noaa::stations(query.origin).await?;
            let nearest = stations
                .iter()
                .filter(|s| s.tidal && region.contains(s.lat, s.lng))
                .min_by(|a, b| {
                    region
                        .distance_m(a.lat, a.lng)
                        .total_cmp(&region.distance_m(b.lat, b.lng))
                });
            let Some(station) = nearest else {
                return Ok(Vec::new());
            };
            let (levels, predictions) = try_join!(
                noaa::levels(query.origin, &station.id),
                noaa::predictions(query.origin, &station.id, query.now)
            )?;
            Ok(turns(station, &levels, &predictions, query.now))
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_a_fresh_turn_even_after_an_earlier_reversal() {
        let station = Station {
            id: "x".into(),
            name: "Harbor".into(),
            lat: 0.,
            lng: 0.,
            tidal: true,
        };
        let start: DateTime<Utc> = "2026-11-22T11:12:00Z".parse().unwrap();
        let expected = start + TimeDelta::minutes(48);
        for (kind, sign, code) in [(Extremum::High, 1., "H"), (Extremum::Low, -1., "L")] {
            let predictions = [PredictedTurn { at: expected, kind }];
            let mut readings: Vec<_> =
                [1., 1.02, 1.04, 1.02, 1., 1.07, 1.12, 1.16, 1.20, 1.16, 1.12]
                    .into_iter()
                    .enumerate()
                    .map(|(i, m)| WaterLevel {
                        at: start + TimeDelta::minutes(i as i64 * 6),
                        metres: m * sign,
                    })
                    .collect();
            let at = |minutes| expected + TimeDelta::minutes(minutes);
            assert!(turns(&station, &readings, &predictions, at(11)).is_empty());
            for minutes in [12, 13, 26] {
                let events = turns(&station, &readings, &predictions, at(minutes));
                assert_eq!(events.len(), 1);
                assert_eq!(events[0].event.occurred_at, expected);
                assert_eq!(
                    events[0].event.id,
                    format!("tide:noaa:x:{code}:{}", expected.timestamp())
                );
            }
            assert!(turns(&station, &readings, &predictions, at(27)).is_empty());
            readings.remove(9);
            assert!(turns(&station, &readings, &predictions, at(13)).is_empty());
        }
    }
}
