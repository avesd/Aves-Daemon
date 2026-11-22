use crate::Place;
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct LastTrain {
    #[serde(flatten)]
    pub place: Place,
    pub station: String,
    pub line: String,
    pub destination: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub destination_name: Option<String>,
}
