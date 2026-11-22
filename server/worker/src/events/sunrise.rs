use std::cell::RefCell;

use avesd_events::{Event, Payload, Place, sunrise::Sunrise};
use chrono::{DateTime, Days, NaiveDate, TimeDelta, Utc};
use chrono_tz::Tz;
use futures_util::future::LocalBoxFuture;

use super::{Candidate, EventProvider, EventResult, Query, Scope};
use crate::sources::{
    places::{Location, PLACES},
    solar::rise,
};

const WINDOW: TimeDelta = TimeDelta::minutes(15);

struct Rise {
    time: DateTime<Utc>,
    difference_minutes: i32,
}

impl Rise {
    fn event(&self, place: &Location, now: DateTime<Utc>) -> Option<Candidate> {
        if !(TimeDelta::zero()..WINDOW).contains(&(now - self.time)) {
            return None;
        }
        Some(Candidate {
            expires_at: self.time + WINDOW,
            event: Event {
                id: format!(
                    "sunrise:{}:{}",
                    place.key,
                    self.time.with_timezone(&place.zone).date_naive()
                ),
                occurred_at: self.time.fixed_offset(),
                payload: Payload::Sunrise(Sunrise {
                    place: Place {
                        place: place.name.clone(),
                        time_zone: place.zone.name().into(),
                        local_name: None,
                    },
                    minutes_later_than_yesterday: self.difference_minutes,
                }),
            },
        })
    }
}

// The local solar date can fall on either side of the UTC date at the date line.
fn daily<'a>(place: &'a Location<'_>, utc_day: NaiveDate) -> impl Iterator<Item = Rise> + 'a {
    let midnight = utc_day.and_hms_opt(0, 0, 0).unwrap().and_utc();
    [-1, 0, 1].into_iter().filter_map(move |offset| {
        let date = utc_day + TimeDelta::days(offset);
        let time = rise(place.lat, place.lon, date)?;
        if time + WINDOW <= midnight || time >= midnight + Days::new(1) {
            return None;
        }
        let yesterday = rise(place.lat, place.lon, date.pred_opt()?)?;
        let civil = |t: DateTime<Utc>| t.with_timezone(&place.zone).naive_local();
        let difference = civil(time) - civil(yesterday) - TimeDelta::days(1);
        Some(Rise {
            time,
            difference_minutes: (difference.num_seconds() as f64 / 60.).round() as i32,
        })
    })
}

#[derive(Default)]
struct Almanac {
    day: Option<NaiveDate>,
    rises: Vec<(usize, Rise)>,
}

thread_local! { static ALMANAC: RefCell<Almanac> = RefCell::default(); }

fn candidates(scope: Scope, now: DateTime<Utc>) -> Vec<Candidate> {
    let day = now.date_naive();
    ALMANAC.with_borrow_mut(|almanac| {
        if almanac.day != Some(day) {
            almanac.rises = PLACES
                .iter()
                .enumerate()
                .flat_map(|(i, place)| daily(place, day).map(move |rise| (i, rise)))
                .collect();
            almanac.day = Some(day);
        }
        match scope {
            Scope::Worldwide => almanac
                .rises
                .iter()
                .filter_map(|(i, rise)| rise.event(&PLACES[*i], now))
                .collect(),
            Scope::Nearby { id, region } => {
                let named: Vec<_> = PLACES
                    .iter()
                    .enumerate()
                    .filter(|(_, p)| region.contains(p.lat, p.lon))
                    .map(|(i, _)| i)
                    .collect();
                if !named.is_empty() {
                    return almanac
                        .rises
                        .iter()
                        .filter(|(i, _)| named.contains(i))
                        .filter_map(|(i, rise)| rise.event(&PLACES[*i], now))
                        .collect();
                }
                let (lat, lon) = region.center_degrees();
                let place = Location {
                    key: id,
                    name: format!("{lat:.2}°, {lon:.2}° (UTC)"),
                    lat,
                    lon,
                    zone: Tz::UTC,
                };
                daily(&place, day)
                    .filter_map(|rise| rise.event(&place, now))
                    .collect()
            }
        }
    })
}

pub struct Sunrises;

impl EventProvider for Sunrises {
    fn events<'a>(&self, query: Query<'a>, scope: Scope<'a>) -> LocalBoxFuture<'a, EventResult> {
        Box::pin(async move { Ok(candidates(scope, query.now)) })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use avesd_core::region::Region;

    #[test]
    fn only_recent_sunrises_play_and_their_ids_do_not_depend_on_the_request() {
        let tokyo = PLACES.iter().find(|p| p.key == "Asia/Tokyo").unwrap();
        let date = NaiveDate::from_ymd_opt(2026, 11, 22).unwrap();
        let time = rise(tokyo.lat, tokyo.lon, date).unwrap();
        assert!(
            (time - "2026-11-21T21:23:00Z".parse::<DateTime<Utc>>().unwrap())
                .num_minutes()
                .abs()
                < 6
        );
        let id = "sunrise:Asia/Tokyo:2026-11-22";
        let world_has_tokyo = |at| {
            candidates(Scope::Worldwide, at)
                .iter()
                .any(|c| c.event.id == id)
        };
        assert!(!world_has_tokyo(time - TimeDelta::seconds(1)));
        assert!(world_has_tokyo(time));
        assert!(!world_has_tokyo(time + WINDOW));
        assert!(rise(85., 20., date).is_none());

        // A user outside any catalog city still gets sunrise at the cell center.
        let id = "86283082fffffff";
        let region = Region::from_id(id).unwrap();
        let (lat, lon) = region.center_degrees();
        let at = rise(lat, lon, date).unwrap();
        let nearby = candidates(
            Scope::Nearby {
                id,
                region: &region,
            },
            at,
        );
        assert_eq!(nearby.len(), 1);
        assert!(nearby[0].event.id.starts_with("sunrise:86283082fffffff:"));
    }
}
