//! Wire format of GET /v1/regions/{region_id}/aircraft.
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct Snapshot {
    pub region_id: String,
    pub fetched_at: DateTime<Utc>,
    pub aircraft: Vec<Aircraft>,
}
#[derive(Debug, Serialize, Deserialize)]
pub struct Aircraft {
    pub aircraft_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub callsign: Option<String>,
    pub latitude: f64,
    pub longitude: f64,
    pub position_at: DateTime<Utc>,
    pub ground_track_deg: Option<f64>,
}
