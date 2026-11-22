mod flyover;
mod sunrise;
mod tide;

use crate::sources::SourceFailure;
use avesd_core::region::Region;
use avesd_events::Event;
use chrono::{DateTime, Utc};
use futures_util::future::LocalBoxFuture;
use worker::Env;

#[derive(Clone, Copy)]
pub enum Scope<'a> {
    Nearby { id: &'a str, region: &'a Region },
    Worldwide,
}

#[derive(Clone, Copy)]
pub struct Query<'a> {
    pub env: &'a Env,
    pub origin: &'a str,
    pub now: DateTime<Utc>,
}

#[derive(serde::Serialize, serde::Deserialize)]
pub struct Candidate {
    pub event: Event,
    pub expires_at: DateTime<Utc>,
}

pub type EventResult = Result<Vec<Candidate>, SourceFailure>;

pub trait EventProvider: Sync {
    fn events<'a>(&self, query: Query<'a>, scope: Scope<'a>) -> LocalBoxFuture<'a, EventResult>;
}

pub const PROVIDERS: &[&dyn EventProvider] =
    &[&flyover::Flyovers, &sunrise::Sunrises, &tide::Tides];
