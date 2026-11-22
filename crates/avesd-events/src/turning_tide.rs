use crate::Place;
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Turn {
    HighToFalling,
    LowToRising,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TurningTide {
    #[serde(flatten)]
    pub place: Place,
    pub turn: Turn,
}
