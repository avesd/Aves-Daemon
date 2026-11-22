use std::collections::BTreeMap;

use avesd_core::region::Region;
use avesd_events::aircraft::{Aircraft, Snapshot};
use chrono::DateTime;
use serde::Deserialize;
use serde_json::Value;

use super::aircraft::MAX_POSITION_AGE;
const CLOCK_SKEW_MS: i64 = 2_000;

#[derive(Deserialize)]
pub struct Feed {
    now: i64, // adsb.lol v2 uses Unix milliseconds.
    ac: Vec<Observation>,
    msg: Option<String>,
}

#[derive(Deserialize)]
struct Observation {
    hex: Option<String>,
    flight: Option<String>,
    lat: Option<f64>,
    lon: Option<f64>,
    seen_pos: Option<f64>,
    track: Option<f64>,
    alt_baro: Option<Value>,
    ground: Option<bool>,
}

impl Observation {
    fn aircraft(self, region: &Region, source_ms: i64, fetched_ms: i64) -> Option<Aircraft> {
        if self.ground == Some(true)
            || self.alt_baro.as_ref().and_then(Value::as_str) == Some("ground")
        {
            return None;
        }
        let (latitude, longitude) = (self.lat?, self.lon?);
        let age_seconds = self.seen_pos?;
        if !region.contains(latitude, longitude)
            || !(0.0..=MAX_POSITION_AGE.as_seconds_f64()).contains(&age_seconds)
        {
            return None;
        }
        let position_ms = source_ms.checked_sub((age_seconds * 1000.0).round() as i64)?;
        if !(-CLOCK_SKEW_MS..=MAX_POSITION_AGE.num_milliseconds())
            .contains(&fetched_ms.checked_sub(position_ms)?)
        {
            return None;
        }
        let hex = self.hex?;
        let (namespace, address) = match hex.strip_prefix('~') {
            Some(address) => ("adsblol", address),
            None => ("icao24", hex.as_str()),
        };
        if address.len() != 6 || !address.bytes().all(|b| b.is_ascii_hexdigit()) {
            return None;
        }
        Some(Aircraft {
            aircraft_id: format!("{namespace}:{}", address.to_ascii_lowercase()),
            callsign: self
                .flight
                .map(|s| s.trim().to_owned())
                .filter(|s| !s.is_empty()),
            latitude,
            longitude,
            position_at: DateTime::from_timestamp_millis(position_ms)?,
            ground_track_deg: self.track.filter(|track| (0.0..360.0).contains(track)),
        })
    }
}

impl Feed {
    pub fn snapshot(self, region_id: &str, region: &Region, fetched_ms: i64) -> Option<Snapshot> {
        if self.msg.as_deref().is_some_and(|msg| msg != "No error")
            || !(-CLOCK_SKEW_MS..=MAX_POSITION_AGE.num_milliseconds())
                .contains(&fetched_ms.checked_sub(self.now)?)
        {
            return None;
        }
        let mut latest = BTreeMap::<String, Aircraft>::new();
        for aircraft in self
            .ac
            .into_iter()
            .filter_map(|row| row.aircraft(region, self.now, fetched_ms))
        {
            if latest
                .get(&aircraft.aircraft_id)
                .is_none_or(|prev| prev.position_at < aircraft.position_at)
            {
                latest.insert(aircraft.aircraft_id.clone(), aircraft);
            }
        }
        Some(Snapshot {
            region_id: region_id.to_owned(),
            fetched_at: DateTime::from_timestamp_millis(fetched_ms)?,
            aircraft: latest.into_values().collect(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    const ID: &str = "86283082fffffff";

    #[test]
    fn snapshot_keeps_the_latest_fresh_airborne_position_in_the_circle() {
        let region = Region::from_id(ID).unwrap();
        let (lat, lon) = region.center_degrees();
        let row = json!({"hex":"ABC123","lat":lat,"lon":lon,"seen_pos":2.5,"track":45});
        let mut older_duplicate = row.clone();
        older_duplicate["seen_pos"] = json!(4);
        let mut rows = vec![row.clone(), older_duplicate];
        for (key, value) in [
            ("seen_pos", json!(29)),
            ("alt_baro", json!("ground")),
            ("lat", json!(0)),
            ("lon", Value::Null),
            ("seen_pos", Value::Null),
        ] {
            let mut record = row.clone();
            record["hex"] = json!("aaaaaa");
            record[key] = value;
            rows.push(record);
        }
        let feed: Feed = serde_json::from_value(json!({"now":1000000, "ac":rows})).unwrap();
        let result = feed.snapshot(ID, &region, 1002000).unwrap();
        assert_eq!(result.aircraft.len(), 1);
        assert_eq!(result.aircraft[0].aircraft_id, "icao24:abc123");
        assert_eq!(result.aircraft[0].position_at.timestamp_millis(), 997500);
        assert_eq!(result.aircraft[0].ground_track_deg, Some(45.0));
    }

    #[test]
    fn fresh_empty_snapshot_is_distinct_from_expired_feed() {
        let region = Region::from_id(ID).unwrap();
        let feed = || serde_json::from_value::<Feed>(json!({"now":1000000,"ac":[]})).unwrap();
        assert!(
            feed()
                .snapshot(ID, &region, 1000000)
                .unwrap()
                .aircraft
                .is_empty()
        );
        assert!(feed().snapshot(ID, &region, 1030001).is_none());
    }
}
