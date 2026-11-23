//! Source snapshots preserve the distinction between an observation and a plan.
use chrono::{DateTime, NaiveDateTime, NaiveTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct Snapshot {
    pub fetched_at: DateTime<Utc>,
    #[serde(flatten)]
    pub data: BridgeData,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "source", rename_all = "snake_case")]
pub enum BridgeData {
    Seaway {
        records: Vec<SeawayStatus>,
    },
    TowerBridge {
        records: Vec<TowerLift>,
    },
    Sdot {
        records: Vec<CompletedOpening>,
    },
    Ndw {
        published_at: DateTime<Utc>,
        records: Vec<RoadMeasure>,
    },
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SeawayStatus {
    pub region: String,
    pub bridge: String,
    pub status: String,
    /// Local time (America/Toronto). The operator does not provide a date.
    pub raised_since_local: Option<NaiveTime>,
    pub next_arrival_local: Option<NaiveTime>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TowerLift {
    pub scheduled_at: DateTime<Utc>,
    pub vessel: String,
    pub direction: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CompletedOpening {
    pub bridge_id: String,
    pub bridge: String,
    /// SDOT supplies floating timestamps in America/Los_Angeles.
    pub opened_local: NaiveDateTime,
    pub closed_local: NaiveDateTime,
    pub latitude: f64,
    pub longitude: f64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct RoadMeasure {
    pub record_id: String,
    pub location_code: String,
    pub location_system: String,
    pub latitude: f64,
    pub longitude: f64,
    pub probability: String,
    pub action_status: String,
    pub validity_status: String,
    pub starts_at: DateTime<Utc>,
    pub ends_at: Option<DateTime<Utc>>,
}
