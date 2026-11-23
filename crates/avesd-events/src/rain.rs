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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub previous_intensity: Option<Intensity>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub current_intensity: Option<Intensity>,
}
