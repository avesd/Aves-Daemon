mod adsb;
pub mod aircraft;
pub mod noaa;
pub mod places;
pub mod solar;
pub mod water_level;

pub struct SourceFailure {
    pub retry_after: Option<String>,
}

impl From<worker::Error> for SourceFailure {
    fn from(error: worker::Error) -> Self {
        worker::console_warn!("Event provider failed: {error}");
        Self { retry_after: None }
    }
}
