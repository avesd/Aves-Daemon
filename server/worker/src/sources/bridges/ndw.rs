use super::ParseResult;
use avesd_events::bridges::{BridgeData, RoadMeasure};
use flate2::read::GzDecoder;
use roxmltree::{Document, Node};
use std::io::Read;

pub(super) const URL: &str = "https://opendata.ndw.nu/planningsfeed_brugopeningen.xml.gz";
const XML_LIMIT: usize = 8 * 1024 * 1024;

fn field<'a>(node: Node<'a, '_>, tag: &str) -> Option<&'a str> {
    node.descendants().find(|n| n.has_tag_name(tag))?.text()
}

pub(super) fn parse(bytes: &[u8]) -> ParseResult<BridgeData> {
    // Some HTTP clients already decode a gzipped response body.
    let mut inflated = Vec::new();
    let xml = if bytes.starts_with(&[0x1f, 0x8b]) {
        GzDecoder::new(bytes)
            .take(XML_LIMIT as u64 + 1)
            .read_to_end(&mut inflated)?;
        inflated.as_slice()
    } else {
        bytes
    };
    if xml.len() > XML_LIMIT {
        return Err("NDW XML exceeds size limit".into());
    }
    let doc = Document::parse_with_options(
        std::str::from_utf8(xml)?,
        roxmltree::ParsingOptions {
            nodes_limit: 350_000,
            ..Default::default()
        },
    )?;
    let publication = doc
        .descendants()
        .find(|n| n.has_tag_name("payload") || n.has_tag_name("payloadPublication"))
        .ok_or("missing NDW publication")?;
    let published_at = field(publication, "publicationTime")
        .ok_or("missing NDW publication time")?
        .parse()?;
    let mut records = Vec::new();
    for row in publication
        .descendants()
        .filter(|n| n.has_tag_name("situationRecord"))
    {
        if field(row, "generalNetworkManagementType") != Some("bridgeSwingInOperation") {
            continue;
        }
        let required = |tag| field(row, tag).ok_or_else(|| format!("missing NDW {tag}"));
        records.push(RoadMeasure {
            record_id: row.attribute("id").ok_or("missing NDW record id")?.into(),
            location_code: required("externalLocationCode")?.into(),
            location_system: required("externalReferencingSystem")?.into(),
            latitude: required("latitude")?.parse()?,
            longitude: required("longitude")?.parse()?,
            probability: required("probabilityOfOccurrence")?.into(),
            action_status: required("operatorActionStatus")?.into(),
            validity_status: required("validityStatus")?.into(),
            starts_at: required("overallStartTime")?.parse()?,
            ends_at: field(row, "overallEndTime").map(str::parse).transpose()?,
        });
    }
    Ok(BridgeData::Ndw {
        published_at,
        records,
    })
}
