use chrono::{DateTime, Utc};

use serde::{Deserialize, Serialize};

#[derive(Deserialize, Serialize)]
pub struct Station {
    pub id: String,
    pub name: String,
    pub lat: f64,
    pub lng: f64,
    pub tidal: bool,
}

#[derive(Clone, Copy)]
pub struct WaterLevel {
    pub at: DateTime<Utc>,
    pub metres: f64,
}

#[derive(Clone, Copy)]
pub enum Extremum {
    High,
    Low,
}

pub struct PredictedTurn {
    pub at: DateTime<Utc>,
    pub kind: Extremum,
}
