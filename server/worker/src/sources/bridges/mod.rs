mod ndw;
mod sdot;
mod seaway;
mod tower;

use super::SourceFailure;
use avesd_events::bridges::{BridgeData, Snapshot};
use chrono::DateTime;
use futures_util::{
    StreamExt,
    future::{Either, select},
};
use scraper::{ElementRef, Selector};
use std::time::Duration;
use worker::{Cache, Date, Delay, Fetch, Method, Request, Response};

type ParseResult<T> = std::result::Result<T, Box<dyn std::error::Error>>;
type Result<T> = std::result::Result<T, SourceFailure>;

fn selector(css: &str) -> Selector {
    Selector::parse(css).expect("static bridge CSS selector")
}

fn text(element: ElementRef<'_>) -> String {
    element
        .text()
        .flat_map(str::split_whitespace)
        .collect::<Vec<_>>()
        .join(" ")
}

fn parsed<T>(result: ParseResult<T>) -> Result<T> {
    result.map_err(|error| {
        worker::console_warn!("Bridge source parse failed: {error}");
        SourceFailure { retry_after: None }
    })
}

async fn download(url: &str) -> Result<Vec<u8>> {
    let mut response = Fetch::Request(Request::new(url, Method::Get)?)
        .send()
        .await?;
    if response.status_code() != 200 {
        return Err(SourceFailure {
            retry_after: response.headers().get("Retry-After")?,
        });
    }
    let mut bytes = Vec::new();
    let mut stream = response.stream()?;
    while let Some(chunk) = stream.next().await {
        let chunk = chunk?;
        if bytes.len() + chunk.len() > 8 * 1024 * 1024 {
            return Err(SourceFailure { retry_after: None });
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok(bytes)
}

#[derive(Clone, Copy)]
pub(crate) enum Source {
    Seaway,
    TowerBridge,
    Sdot,
    Ndw,
}

impl Source {
    pub(crate) fn from_slug(slug: &str) -> Option<Self> {
        match slug {
            "seaway" => Some(Self::Seaway),
            "tower_bridge" => Some(Self::TowerBridge),
            "sdot" => Some(Self::Sdot),
            "ndw" => Some(Self::Ndw),
            _ => None,
        }
    }

    async fn load(self) -> Result<BridgeData> {
        Ok(match self {
            Self::Seaway => BridgeData::Seaway {
                records: seaway::load().await?,
            },
            Self::TowerBridge => BridgeData::TowerBridge {
                records: parsed(tower::parse(&download(tower::URL).await?))?,
            },
            Self::Sdot => BridgeData::Sdot {
                records: parsed(sdot::parse(&download(sdot::URL).await?))?,
            },
            Self::Ndw => parsed(ndw::parse(&download(ndw::URL).await?))?,
        })
    }

    pub(crate) async fn snapshot(self, cache_key: &str) -> worker::Result<Response> {
        let cache = Cache::default();
        if let Ok(Some(hit)) = cache.get(cache_key, false).await {
            return Ok(hit);
        }
        let deadline = Delay::from(Duration::from_secs(8));
        let data = match select(Box::pin(self.load()), Box::pin(deadline)).await {
            Either::Left((Ok(data), _)) => data,
            either => {
                let mut response = Response::error("Bridge source unavailable", 503)?;
                if let Either::Left((Err(failure), _)) = either
                    && let Some(delay) = failure.retry_after
                {
                    response.headers_mut().set("Retry-After", &delay)?;
                }
                return Ok(response);
            }
        };
        let ttl = match self {
            Self::Seaway | Self::Ndw => 60,
            Self::TowerBridge => 900,
            Self::Sdot => 3600,
        };
        let fetched_at = DateTime::from_timestamp_millis(Date::now().as_millis() as i64).unwrap();
        let mut response = Response::from_json(&Snapshot { fetched_at, data })?;
        response
            .headers_mut()
            .set("Cache-Control", &format!("public, max-age={ttl}"))?;
        if let Err(error) = cache.put(cache_key, response.cloned()?).await {
            worker::console_warn!("Bridge cache write failed: {error}");
        }
        Ok(response)
    }
}

#[cfg(test)]
mod tests;
