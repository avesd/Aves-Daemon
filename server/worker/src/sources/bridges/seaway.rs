use super::{ParseResult, selector, text};
use avesd_events::bridges::SeawayStatus;
use chrono::NaiveTime;
use scraper::Html;

pub(super) const PAGES: [(&str, &str); 3] = [
    (
        "st_catharines_thorold",
        "https://www.seaway-greatlakes.com/bridgestatus/detailsnai?key=BridgeSCT",
    ),
    (
        "port_colborne",
        "https://www.seaway-greatlakes.com/bridgestatus/detailsnai?key=BridgePC",
    ),
    (
        "montreal_south_shore",
        "https://www.seaway-greatlakes.com/bridgestatus/detailsmai?key=BridgeM",
    ),
];

pub(super) fn parse(region: &str, bytes: &[u8]) -> ParseResult<Vec<SeawayStatus>> {
    let html = Html::parse_document(std::str::from_utf8(bytes)?);
    let name = selector(".lgtextblack");
    let status = selector("[id=status]");
    let arrival = selector(".lgtextblack10");
    let mut records = Vec::new();
    for table in html.select(&selector("table[id=grey_box]")) {
        let bridge = text(table.select(&name).next().ok_or("missing Seaway bridge")?);
        let status = text(
            table
                .select(&status)
                .next()
                .ok_or("missing Seaway status")?,
        );
        let raised_since_local = status
            .split_once("raised since ")
            .and_then(|(_, v)| v.split_once(')'))
            .and_then(|(v, _)| NaiveTime::parse_from_str(v, "%H:%M").ok());
        let next_arrival_local = table.select(&arrival).map(text).find_map(|v| {
            NaiveTime::parse_from_str(v.strip_prefix("Next Arrival: ")?, "%H:%M").ok()
        });
        if bridge.is_empty() || status.is_empty() {
            return Err("empty Seaway status row".into());
        }
        records.push(SeawayStatus {
            region: region.into(),
            bridge,
            status,
            raised_since_local,
            next_arrival_local,
        });
    }
    if records.is_empty() {
        return Err("missing Seaway status table".into());
    }
    Ok(records)
}

pub(super) async fn load() -> super::Result<Vec<SeawayStatus>> {
    let pages = futures_util::future::try_join_all(PAGES.map(|(region, url)| async move {
        let bytes = super::download(url).await?;
        super::parsed(parse(region, &bytes))
    }))
    .await?;
    Ok(pages.into_iter().flatten().collect())
}
