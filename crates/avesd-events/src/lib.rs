//! An occurrence has a stable ID and timestamp. Its payload describes world facts.
pub mod bridge_lift;
pub mod flyover;
pub mod last_train;
pub mod rain;
pub mod sunrise;
pub mod turning_tide;

use chrono::{DateTime, FixedOffset};
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct Event {
    pub id: String,
    pub occurred_at: DateTime<FixedOffset>,
    #[serde(flatten)]
    pub payload: Payload,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "snake_case")]
pub enum Payload {
    Flyover(flyover::Flyover),
    Rain(rain::Rain),
    Sunrise(sunrise::Sunrise),
    BridgeLift(bridge_lift::BridgeLift),
    TurningTide(turning_tide::TurningTide),
    LastTrain(last_train::LastTrain),
}

/// Locality and optional localized place name supplied with an observation.
#[derive(Debug, Serialize, Deserialize)]
pub struct Place {
    pub place: String,
    pub time_zone: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub local_name: Option<String>,
}
