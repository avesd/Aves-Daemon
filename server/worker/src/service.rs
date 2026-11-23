use avesd_core::region::Region;
use avesd_events::Event;
use chrono::{DateTime, Utc};
use futures_util::future::{Either, join_all, select};
use std::{collections::HashSet, time::Duration};
use worker::{Date, Delay, Env, Response, Result, js_sys::Math};

use crate::events::{Candidate, EventProvider, EventResult, PROVIDERS, Query, Scope};

use crate::sources::SourceFailure;

struct Policy {
    nearby_percent: u8,
    drop_percent: u8,
}

impl Policy {
    fn read(env: &Env) -> Result<Self> {
        let percent = |name, default| match env.var(name) {
            Err(_) => Ok(default),
            Ok(value) => value
                .to_string()
                .parse::<u8>()
                .ok()
                .filter(|n| *n <= 100)
                .ok_or_else(|| worker::Error::RustError(format!("Invalid percentage for {name}"))),
        };
        Ok(Self {
            nearby_percent: percent("EVENT_NEARBY_PERCENT", 70)?,
            drop_percent: percent("EVENT_DROP_PERCENT", 80)?,
        })
    }
}

#[derive(Default)]
struct Pools {
    nearby: Vec<Candidate>,
    world: Vec<Candidate>,
}

enum Decision<'a> {
    Play(&'a Event),
    Quiet,
    Empty,
}

impl Pools {
    fn choose<'a>(
        &'a self,
        now: DateTime<Utc>,
        played: &[String],
        policy: &Policy,
        mut random: impl FnMut() -> f64,
    ) -> Decision<'a> {
        let mut seen: HashSet<&str> = played.iter().map(String::as_str).collect();
        let mut eligible = |candidate: &&'a Candidate| {
            candidate.expires_at > now && seen.insert(candidate.event.id.as_str())
        };
        let mut candidates: Vec<_> = self.nearby.iter().filter(&mut eligible).collect();
        let nearby_count = candidates.len();
        candidates.extend(self.world.iter().filter(eligible));
        if candidates.is_empty() {
            return Decision::Empty;
        }
        if random() * 100. < f64::from(policy.drop_percent) {
            return Decision::Quiet;
        }
        let (nearby, world) = candidates.split_at(nearby_count);
        let pool = if world.is_empty()
            || (!nearby.is_empty() && random() * 100. < f64::from(policy.nearby_percent))
        {
            nearby
        } else {
            world
        };
        let index = (random() * pool.len() as f64) as usize;
        Decision::Play(&pool[index].event)
    }
}

async fn load<'a>(provider: &dyn EventProvider, query: Query<'a>, scope: Scope<'a>) -> EventResult {
    let deadline = Box::pin(Delay::from(Duration::from_secs(4)));
    match select(provider.events(query, scope), deadline).await {
        Either::Left((result, _)) => result,
        Either::Right(_) => Err(SourceFailure { retry_after: None }),
    }
}

pub async fn poll(
    env: &Env,
    origin: &str,
    id: &str,
    region: &Region,
    played: &[String],
) -> Result<Response> {
    let clock = || DateTime::from_timestamp_millis(Date::now().as_millis() as i64).unwrap();
    let policy = Policy::read(env)?;
    let query = Query {
        env,
        origin,
        now: clock(),
    };
    let scopes = [Scope::Nearby { id, region }, Scope::Worldwide];
    let jobs = scopes.into_iter().flat_map(|scope| {
        PROVIDERS
            .iter()
            .map(move |p| async move { (scope, load(*p, query, scope).await) })
    });
    let mut pools = Pools::default();
    let mut failure = None;
    for (scope, result) in join_all(jobs).await {
        match (scope, result) {
            (Scope::Nearby { .. }, Ok(events)) => pools.nearby.extend(events),
            (Scope::Worldwide, Ok(events)) => pools.world.extend(events),
            (_, Err(error)) => {
                if failure.is_none() || error.retry_after.is_some() {
                    failure = Some(error);
                }
            }
        }
    }
    let mut response = match pools.choose(clock(), played, &policy, Math::random) {
        Decision::Play(event) => Response::from_json(event)?,
        Decision::Empty if failure.is_some() => {
            let mut unavailable = Response::error("Event source unavailable", 503)?;
            if let Some(value) = failure.and_then(|e| e.retry_after) {
                unavailable.headers_mut().set("Retry-After", &value)?;
            }
            unavailable
        }
        Decision::Empty | Decision::Quiet => Response::empty()?.with_status(204),
    };
    response
        .headers_mut()
        .set("Cache-Control", "private, no-store")?;
    Ok(response)
}

#[cfg(test)]
mod tests {
    use super::*;
    use avesd_events::{Payload, flyover::Flyover};
    use chrono::TimeDelta;

    fn example(id: &str) -> Candidate {
        Candidate {
            event: Event {
                id: id.into(),
                occurred_at: DateTime::UNIX_EPOCH.fixed_offset(),
                payload: Payload::Flyover(Flyover::default()),
            },
            expires_at: DateTime::UNIX_EPOCH + TimeDelta::minutes(15),
        }
    }

    #[test]
    fn chooses_scope_after_filtering_and_drops_only_once() {
        let pools = Pools {
            nearby: vec![example("near")],
            world: vec![example("near"), example("a"), example("b")],
        };
        let now = DateTime::UNIX_EPOCH;
        let policy = Policy {
            nearby_percent: 70,
            drop_percent: 80,
        };
        let select = |roll, played: &[String]| {
            let mut rolls = [0.9, roll, 0.0].into_iter();
            pools.choose(now, played, &policy, || rolls.next().unwrap())
        };
        assert!(matches!(select(0.69, &[]), Decision::Play(e) if e.id == "near"));
        assert!(matches!(select(0.70, &[]), Decision::Play(e) if e.id == "a"));
        assert!(matches!(select(0.1, &["near".into()]), Decision::Play(e) if e.id == "a"));
        assert!(
            matches!(select(0.99, &["a".into(), "b".into()]), Decision::Play(e) if e.id == "near")
        );
        let mut one = Some(0.79);
        assert!(matches!(
            pools.choose(now, &[], &policy, || one.take().unwrap()),
            Decision::Quiet
        ));
        assert!(matches!(
            pools.choose(
                now + TimeDelta::minutes(15),
                &[],
                &policy,
                || unreachable!()
            ),
            Decision::Empty
        ));
    }
}
