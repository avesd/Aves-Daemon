use serde::{Deserialize, Serialize};

#[derive(Default, Debug, Serialize, Deserialize)]
pub struct Flyover {
    pub aircraft_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub airline_code: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub airline_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub airline_mark: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub flight_number: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub callsign: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub origin: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub destination: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub origin_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub destination_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub aircraft_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
}
