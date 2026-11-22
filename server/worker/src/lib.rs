mod events;
mod service;
mod sources;

use avesd_core::region::Region;
use worker::{Context, Env, Method, Request, Response, Result, event};

#[event(fetch)]
pub async fn fetch(request: Request, env: Env, _context: Context) -> Result<Response> {
    let url = request.url()?;
    let Some((id, resource)) = url
        .path()
        .strip_prefix("/v1/regions/")
        .and_then(|s| s.split_once('/'))
    else {
        return Response::error("Not Found", 404);
    };
    if !matches!(resource, "aircraft" | "event") {
        return Response::error("Not Found", 404);
    }
    if request.method() != Method::Get {
        let mut response = Response::error("Method Not Allowed", 405)?;
        response.headers_mut().set("Allow", "GET")?;
        return Ok(response);
    }
    let Some(region) = Region::from_id(id) else {
        return Response::error("Invalid resolution-six H3 cell", 400);
    };
    let id = id.to_owned();
    let played = if resource == "event" {
        let mut ids = Vec::new();
        for (_, value) in url.query_pairs().filter(|(key, _)| key == "played") {
            if ids.len() >= 64 || value.len() > 256 {
                return Response::error("Invalid playback history", 400);
            }
            ids.push(value.into_owned());
        }
        Some(ids)
    } else {
        None
    };
    let origin = url.origin().ascii_serialization();
    match played {
        None => sources::aircraft::snapshot(&origin, &id, &region, &env).await,
        Some(played) => service::poll(&env, &origin, &id, &region, &played).await,
    }
}
