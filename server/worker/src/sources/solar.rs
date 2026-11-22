use chrono::{DateTime, NaiveDate, Utc};
use sunrise::{Coordinates, SolarDay, SolarEvent};

/// The date labels the solar day at this longitude, including across the date line.
pub fn rise(lat: f64, lon: f64, date: NaiveDate) -> Option<DateTime<Utc>> {
    SolarDay::new(Coordinates::new(lat, lon)?, date).event_time(SolarEvent::Sunrise)
}
