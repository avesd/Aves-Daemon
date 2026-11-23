mod events;
mod service;
mod sources;

use avesd_core::region::Region;
use worker::{Context, Env, Method, Request, Response, Result, event};

#[event(fetch)]
pub async fn fetch(request: Request, env: Env, _context: Context) -> Result<Response> {
    let url = request.url()?;
    if let Some(slug) = url.path().strip_prefix("/v1/bridges/") {
        let Some(source) = sources::bridges::Source::from_slug(slug) else {
            return Response::error("Not Found", 404);
        };
        if request.method() != Method::Get {
            return method_not_allowed();
        }
        let key = format!(
            "{}{path}",
            url.origin().ascii_serialization(),
            path = url.path()
        );
        return source.snapshot(&key).await;
    }
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
        return method_not_allowed();
    }
    let Some(region) = Region::from_id(id) else {
        return Response::error("Invalid resolution-six H3 cell", 400);
    };
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
        None => sources::aircraft::snapshot(&origin, id, &region, &env).await,
        Some(played) => service::poll(&env, &origin, id, &region, &played).await,
    }
}

fn method_not_allowed() -> Result<Response> {
    let mut response = Response::error("Method Not Allowed", 405)?;
    response.headers_mut().set("Allow", "GET")?;
    Ok(response)
}
