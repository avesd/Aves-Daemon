use crate::Place;
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct BridgeLift {
    #[serde(flatten)]
    pub place: Place,
    pub bridge: String,
    pub reason: String,
}
