use crate::Place;
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct Sunrise {
    #[serde(flatten)]
    pub place: Place,
    pub minutes_later_than_yesterday: i32,
}
