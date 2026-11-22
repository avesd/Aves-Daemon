use crate::Place;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Intensity {
    None,
    Light,
    Moderate,
    Heavy,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Rain {
    #[serde(flatten)]
    pub place: Place,
    pub previous_intensity: Intensity,
    pub current_intensity: Intensity,
}
