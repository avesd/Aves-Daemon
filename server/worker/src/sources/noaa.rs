use super::{
    SourceFailure,
    water_level::{Extremum, PredictedTurn, Station, WaterLevel},
};
use chrono::{DateTime, NaiveDateTime, TimeDelta, Utc};
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use worker::{Cache, Fetch, Method, Request, Response};

type Result<T> = std::result::Result<T, SourceFailure>;

const DATA: &str = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter";
const STATIONS: &str =
    "https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json?type=waterlevels";

#[derive(Deserialize, Serialize)]
struct Stations {
    stations: Vec<Station>,
}

#[derive(Deserialize, Serialize)]
struct Levels {
    data: Vec<Reading>,
}

#[derive(Deserialize, Serialize)]
struct Reading {
    t: String,
    v: String,
    f: String,
}

#[derive(Deserialize, Serialize)]
struct Predictions {
    predictions: Vec<Prediction>,
}

#[derive(Deserialize, Serialize)]
struct Prediction {
    t: String,
    #[serde(rename = "type")]
    kind: String,
}

async fn cached<T: DeserializeOwned + Serialize>(
    origin: &str,
    key: &str,
    url: &str,
    ttl: u32,
) -> Result<T> {
    let key = format!("{origin}/_sources/noaa/{key}");
    let cache = Cache::default();
    if let Ok(Some(mut hit)) = cache.get(key.as_str(), false).await
        && let Ok(value) = hit.json().await
    {
        return Ok(value);
    }
    let mut upstream = Fetch::Request(Request::new(url, Method::Get)?)
        .send()
        .await?;
    if upstream.status_code() != 200 {
        worker::console_warn!("NOAA returned HTTP {}", upstream.status_code());
        return Err(SourceFailure {
            retry_after: upstream.headers().get("Retry-After")?,
        });
    }
    let value = upstream.json::<T>().await?;
    let mut response = Response::from_json(&value)?;
    response
        .headers_mut()
        .set("Cache-Control", &format!("public, max-age={ttl}"))?;
    if let Err(error) = cache.put(key.as_str(), response).await {
        worker::console_warn!("NOAA cache write failed: {error}");
    }
    Ok(value)
}

pub async fn stations(origin: &str) -> Result<Vec<Station>> {
    Ok(
        cached::<Stations>(origin, "water-level-stations", STATIONS, 86400)
            .await?
            .stations,
    )
}

fn time(raw: &str) -> Option<DateTime<Utc>> {
    NaiveDateTime::parse_from_str(raw, "%Y-%m-%d %H:%M")
        .ok()
        .map(|t| t.and_utc())
}

impl Levels {
    fn observations(self) -> Vec<WaterLevel> {
        let mut readings: Vec<_> = self
            .data
            .into_iter()
            .filter_map(|row| {
                // The last three preliminary flags mark suspect water heights.
                let (_, "0,0,0") = row.f.split_once(',')? else {
                    return None;
                };
                Some(WaterLevel {
                    at: time(&row.t)?,
                    metres: row.v.parse::<f64>().ok().filter(|v| v.is_finite())?,
                })
            })
            .collect();
        readings.sort_by_key(|r| r.at);
        readings
    }
}

impl Predictions {
    fn turns(self) -> Vec<PredictedTurn> {
        self.predictions
            .into_iter()
            .filter_map(|row| {
                Some(PredictedTurn {
                    at: time(&row.t)?,
                    kind: match row.kind.as_str() {
                        "H" => Extremum::High,
                        "L" => Extremum::Low,
                        _ => return None,
                    },
                })
            })
            .collect()
    }
}

pub async fn levels(origin: &str, station: &str) -> Result<Vec<WaterLevel>> {
    let url = format!(
        "{DATA}?station={station}&product=water_level&range=3&datum=MLLW&time_zone=gmt&units=metric&format=json&application=AvesDaemon"
    );
    Ok(
        cached::<Levels>(origin, &format!("levels/{station}"), &url, 300)
            .await?
            .observations(),
    )
}

pub async fn predictions(
    origin: &str,
    station: &str,
    now: DateTime<Utc>,
) -> Result<Vec<PredictedTurn>> {
    let today = now.format("%Y%m%d");
    let start = (now - TimeDelta::days(1)).format("%Y%m%d").to_string();
    let end = (now + TimeDelta::days(1)).format("%Y%m%d").to_string();
    let url = format!(
        "{DATA}?station={station}&product=predictions&interval=hilo&begin_date={start}&end_date={end}&datum=MLLW&time_zone=gmt&units=metric&format=json&application=AvesDaemon"
    );
    Ok(cached::<Predictions>(
        origin,
        &format!("predictions/{station}/{today}"),
        &url,
        86400,
    )
    .await?
    .turns())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn normalizes_noaa_rows_and_discards_unusable_observations() {
        let rows = [
            ("12:12", "1.2", "1,0,0,0"),
            ("12:06", "1.1", "0,0,1,0"),
            ("12:00", "1", "0,0,0,0"),
            ("12:18", "NaN", "0,0,0,0"),
            ("25:00", "2", "0,0,0,0"),
        ]
        .map(|(t, v, f)| json!({"t":format!("2026-11-22 {t}"), "v":v, "f":f}));
        let readings = serde_json::from_value::<Levels>(json!({"data": rows}))
            .unwrap()
            .observations();
        assert_eq!(
            readings.iter().map(|r| r.metres).collect::<Vec<_>>(),
            [1., 1.2]
        );
        let rows = ["H", "L", "unknown"].map(|kind| json!({"t":"2026-11-22 12:12","type":kind}));
        let predictions = serde_json::from_value::<Predictions>(json!({"predictions": rows}))
            .unwrap()
            .turns();
        assert!(matches!(
            predictions.as_slice(),
            [
                PredictedTurn {
                    kind: Extremum::High,
                    ..
                },
                PredictedTurn {
                    kind: Extremum::Low,
                    ..
                }
            ]
        ));
    }
}
