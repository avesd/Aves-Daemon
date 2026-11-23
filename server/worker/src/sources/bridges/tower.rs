use super::{ParseResult, selector, text};
use avesd_events::bridges::TowerLift;
use chrono::DateTime;
use scraper::Html;

pub(super) const URL: &str = "https://www.towerbridge.org.uk/flat/lift-times";

pub(super) fn parse(bytes: &[u8]) -> ParseResult<Vec<TowerLift>> {
    let html = Html::parse_document(std::str::from_utf8(bytes)?);
    let table = html
        .select(&selector(".bridge-lift-times-flat__table"))
        .next()
        .ok_or("missing Tower Bridge timetable")?;
    let stamp = selector("time[datetime]");
    let vessel = selector(".views-field-field-vessel");
    let direction = selector(".views-field-field-direction");
    let mut records = Vec::new();
    for row in table.select(&selector("tbody tr")) {
        let time = row
            .select(&stamp)
            .next()
            .and_then(|e| e.attr("datetime"))
            .ok_or("missing lift time")?
            .parse()?;
        records.push(TowerLift {
            scheduled_at: DateTime::from_timestamp(time, 0).ok_or("invalid lift time")?,
            vessel: text(row.select(&vessel).next().ok_or("missing vessel field")?),
            direction: text(
                row.select(&direction)
                    .next()
                    .ok_or("missing direction field")?,
            ),
        });
    }
    Ok(records)
}
