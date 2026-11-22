use super::adsb::Feed;
use avesd_core::region::Region;
use worker::{Cache, Date, Env, Fetch, Method, Request, Response, Result};

pub const MAX_POSITION_AGE: chrono::TimeDelta = chrono::TimeDelta::seconds(30);

pub async fn snapshot(origin: &str, id: &str, region: &Region, env: &Env) -> Result<Response> {
    let cache_key = format!("{origin}/v1/regions/{id}/aircraft");
    let cache = Cache::default();
    if let Ok(Some(hit)) = cache.get(&cache_key[..], false).await {
        return Ok(hit);
    }

    let (lat, lon) = region.center_degrees();
    let radius_nm = (region.radius_m() / 1852.0).ceil() as u32;
    let endpoint = format!("https://api.adsb.lol/v2/point/{lat}/{lon}/{radius_nm}");
    let mut upstream = Request::new(&endpoint, Method::Get)?;
    if let Ok(key) = env.secret("ADSB_LOL_API_KEY") {
        upstream.headers_mut()?.set("x-api-key", &key.to_string())?;
    }
    let Ok(mut upstream) = Fetch::Request(upstream).send().await else {
        return unavailable(None);
    };
    if upstream.status_code() != 200 {
        return unavailable(upstream.headers().get("Retry-After")?);
    }
    let Ok(feed) = upstream.json::<Feed>().await else {
        return unavailable(None);
    };
    let Some(snapshot) = feed.snapshot(id, region, Date::now().as_millis() as i64) else {
        return unavailable(None);
    };
    let mut response = Response::from_json(&snapshot)?;
    response
        .headers_mut()
        .set("Cache-Control", "public, max-age=0, s-maxage=15")?;
    if let Err(error) = cache.put(&cache_key[..], response.cloned()?).await {
        worker::console_warn!("Aircraft snapshot cache write failed: {error}");
    }
    Ok(response)
}

fn unavailable(retry_after: Option<String>) -> Result<Response> {
    let mut response = Response::error("Aircraft data unavailable", 503)?;
    response.headers_mut().set("Cache-Control", "no-store")?;
    if let Some(value) = retry_after {
        response.headers_mut().set("Retry-After", &value)?;
    }
    Ok(response)
}
