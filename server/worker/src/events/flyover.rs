use super::{Candidate, EventProvider, Query, Scope};
use crate::sources::{SourceFailure, aircraft};
use avesd_events::{Event, Payload, aircraft::Snapshot, flyover::Flyover};
use chrono::{DateTime, TimeDelta, Utc};
use futures_util::future::LocalBoxFuture;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, btree_map::Entry};
use worker::{
    DurableObject, Env, Method, Request, RequestInit, Response, Result, State, durable_object,
};

pub struct Flyovers;

impl EventProvider for Flyovers {
    fn events<'a>(
        &self,
        query: Query<'a>,
        scope: Scope<'a>,
    ) -> LocalBoxFuture<'a, super::EventResult> {
        Box::pin(async move {
            let Scope::Nearby { id, region } = scope else {
                return Ok(Vec::new());
            };
            let mut response = aircraft::snapshot(query.origin, id, region, query.env).await?;
            if response.status_code() != 200 {
                return Err(SourceFailure {
                    retry_after: response.headers().get("Retry-After")?,
                });
            }
            let stub = query
                .env
                .durable_object("REGIONAL_FLYOVERS")?
                .get_by_name(id)?;
            let mut init = RequestInit::new();
            init.with_method(Method::Post)
                .with_body(Some(response.text().await?.into()));
            let mut passes = stub
                .fetch_with_request(Request::new_with_init(
                    "https://region.internal/passes",
                    &init,
                )?)
                .await?;
            Ok(passes.json().await?)
        })
    }
}
#[derive(Serialize, Deserialize)]
struct Pass {
    first: DateTime<Utc>,
    last: DateTime<Utc>,
}

type Passes = BTreeMap<String, Pass>;

// A quiet region may go fifteen minutes between observations from a single client.
const PASS_GAP: TimeDelta = TimeDelta::minutes(20);

fn candidates(passes: &mut Passes, snapshot: Snapshot) -> (Vec<Candidate>, bool) {
    let previous_len = passes.len();
    passes
        .retain(|_, pass| snapshot.fetched_at - pass.last <= PASS_GAP + aircraft::MAX_POSITION_AGE);
    let mut changed = passes.len() != previous_len;
    let mut eligible = Vec::new();
    for aircraft in snapshot.aircraft {
        let at = aircraft.position_at;
        let pass = match passes.entry(aircraft.aircraft_id.clone()) {
            Entry::Vacant(entry) => {
                changed = true;
                entry.insert(Pass {
                    first: at,
                    last: at,
                })
            }
            Entry::Occupied(entry) => {
                let pass = entry.into_mut();
                if at < pass.first {
                    continue;
                }
                if at > pass.last {
                    if at - pass.last > PASS_GAP {
                        pass.first = at;
                    }
                    pass.last = at;
                    changed = true;
                }
                pass
            }
        };
        let id = format!(
            "flyover:{}:{}:{}",
            snapshot.region_id,
            aircraft.aircraft_id,
            pass.first.timestamp_millis()
        );
        eligible.push(Candidate {
            expires_at: snapshot.fetched_at + TimeDelta::seconds(15),
            event: Event {
                id,
                occurred_at: pass.first.fixed_offset(),
                payload: Payload::Flyover(Flyover {
                    aircraft_id: aircraft.aircraft_id,
                    callsign: aircraft.callsign,
                    ..Flyover::default()
                }),
            },
        });
    }
    (eligible, changed)
}

#[durable_object]
pub struct RegionalFlyovers {
    state: State,
}

impl DurableObject for RegionalFlyovers {
    fn new(state: State, _env: Env) -> Self {
        Self { state }
    }

    async fn fetch(&self, mut request: Request) -> Result<Response> {
        let snapshot = request.json().await?;
        let storage = self.state.storage();
        let mut passes: Passes = storage.get("passes").await?.unwrap_or_default();
        let (eligible, changed) = candidates(&mut passes, snapshot);
        if changed {
            storage.put("passes", passes).await?;
        }
        Response::from_json(&eligible)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn snapshot(time: &str) -> Snapshot {
        serde_json::from_value(json!({
            "region_id":"region","fetched_at":time,
            "aircraft":[{"aircraft_id":"a","callsign":"UAL123","latitude":0,"longitude":0,"position_at":time}]
        })).unwrap()
    }

    #[test]
    fn tracks_occurrences_across_hour_boundaries_and_restart() {
        let mut passes = Passes::new();
        let first = candidates(&mut passes, snapshot("2026-11-22T10:59:00Z"))
            .0
            .pop()
            .unwrap();
        let mut restored = serde_json::from_value(serde_json::to_value(passes).unwrap()).unwrap();
        let next = candidates(&mut restored, snapshot("2026-11-22T11:10:00Z"))
            .0
            .pop()
            .unwrap();
        assert_eq!(first.event.id, next.event.id);
        assert!(
            matches!(next.event.payload, Payload::Flyover(f) if f.callsign.as_deref() == Some("UAL123"))
        );
        let later = candidates(&mut restored, snapshot("2026-11-22T13:00:00Z"))
            .0
            .pop()
            .unwrap();
        assert_ne!(first.event.id, later.event.id);
    }

    #[test]
    fn observation_time_controls_identity_and_only_changes_require_a_write() {
        let mut passes = Passes::new();
        let first = snapshot("2026-11-22T10:00:00Z");
        let (events, changed) = candidates(&mut passes, first);
        assert!(changed);
        let id = &events[0].event.id;
        let mut empty = snapshot("2026-11-22T10:20:05Z");
        empty.aircraft.clear();
        assert!(!candidates(&mut passes, empty).1);

        let delayed = || {
            let mut row = snapshot("2026-11-22T10:19:55Z");
            row.fetched_at += TimeDelta::seconds(15);
            row
        };
        let (events, changed) = candidates(&mut passes, delayed());
        assert!(changed);
        assert_eq!(events[0].event.id, *id);
        let (events, changed) = candidates(&mut passes, delayed());
        assert!(!changed);
        assert_eq!(events[0].event.id, *id);

        let (later, changed) = candidates(&mut passes, snapshot("2026-11-22T10:39:56Z"));
        assert!(changed);
        assert_ne!(later[0].event.id, *id);
        let mut empty = snapshot("2026-11-22T11:01:00Z");
        empty.aircraft.clear();
        assert!(candidates(&mut passes, empty).1);
        assert!(passes.is_empty());
    }
}
