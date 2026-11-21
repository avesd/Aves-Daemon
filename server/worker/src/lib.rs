use worker::{Context, Env, Request, Response, Result, event};

#[event(fetch)]
pub async fn fetch(_request: Request, _env: Env, _context: Context) -> Result<Response> {
    Response::error("Not Found", 404)
}
