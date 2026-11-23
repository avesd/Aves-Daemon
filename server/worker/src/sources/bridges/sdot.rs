use super::ParseResult;
use avesd_events::bridges::CompletedOpening;
use chrono::NaiveDateTime;
use serde::Deserialize;

pub(super) const URL: &str = "https://data.seattle.gov/resource/gm8h-9449.json?$where=entitytype%3D%27Bridge%27&$order=opendatetime%20DESC&$limit=50";

#[derive(Deserialize)]
struct Row {
    entityid: String,
    entityname: String,
    opendatetime: NaiveDateTime,
    closedatetime: NaiveDateTime,
    latitude: String,
    longitude: String,
}

pub(super) fn parse(bytes: &[u8]) -> ParseResult<Vec<CompletedOpening>> {
    serde_json::from_slice::<Vec<Row>>(bytes)?
        .into_iter()
        .map(|r| {
            Ok(CompletedOpening {
                bridge_id: r.entityid,
                bridge: r.entityname,
                opened_local: r.opendatetime,
                closed_local: r.closedatetime,
                latitude: r.latitude.parse()?,
                longitude: r.longitude.parse()?,
            })
        })
        .collect()
}
