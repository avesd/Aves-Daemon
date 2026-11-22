mod bridge_lift;
mod flyover;
mod last_train;
pub mod rain;
mod sunrise;
mod turning_tide;

use super::frame::{Canvas, eased};
use avesd_events::{Payload, turning_tide::Turn};
use rain::RainShower;

pub enum Effect {
    Flyover,
    Rain(RainShower),
    Sunrise,
    BridgeLift,
    TurningTide { rising: bool },
    LastTrain { destination: String, time: String },
}
pub struct Layout {
    pub width: f64,
    pub anchor_x: f64,
}
impl Effect {
    pub fn new(payload: &Payload, seed: u64, local_time: &str) -> Self {
        match payload {
            Payload::Flyover(_) => Self::Flyover,
            Payload::Rain(_) => Self::Rain(RainShower::new(seed)),
            Payload::Sunrise(_) => Self::Sunrise,
            Payload::BridgeLift(_) => Self::BridgeLift,
            Payload::TurningTide(t) => Self::TurningTide {
                rising: matches!(t.turn, Turn::LowToRising),
            },
            Payload::LastTrain(t) => Self::LastTrain {
                destination: t.destination.clone(),
                time: local_time.to_owned(),
            },
        }
    }
    pub fn duration(&self) -> f64 {
        match self {
            Self::Flyover => 2.2,
            Self::Rain(r) => r.duration_ms / 1000.,
            Self::Sunrise => 6.1,
            Self::BridgeLift => 5.85,
            Self::TurningTide { .. } => 7.35,
            Self::LastTrain { .. } => 3.95,
        }
    }
    fn cues(&self) -> Option<[f64; 3]> {
        Some(match self {
            Self::Sunrise => [4.25, 4.50, 4.87],
            Self::BridgeLift => [4.81, 5.04, 5.35],
            Self::TurningTide { .. } => [5.35, 5.62, 5.97],
            Self::LastTrain { .. } => [2.72, 2.94, 3.23],
            _ => return None,
        })
    }
    pub fn ready(&self) -> f64 {
        self.cues().map_or(self.duration(), |c| c[1] + 0.42)
    }
    pub fn sample(
        &self,
        t: f64,
        v: f64,
        dismissal: f64,
        layout: &Layout,
        icon: &mut Canvas,
        scenery: &mut Canvas,
    ) -> [f64; 4] {
        self.draw_icon(t, v, layout, icon);
        self.draw_scenery(t, v, dismissal, layout, scenery)
    }

    pub(super) fn draw_icon(&self, t: f64, v: f64, layout: &Layout, icon: &mut Canvas) {
        icon.0.clear();
        match self {
            Self::Sunrise => sunrise::icon(icon, t),
            Self::BridgeLift => bridge_lift::icon(icon),
            Self::TurningTide { rising } => {
                turning_tide::draw(icon, true, t, v, layout.width - layout.anchor_x, *rising)
            }
            Self::LastTrain { .. } => last_train::icon(icon, t),
            Self::Rain(_) | Self::Flyover => {}
        }
    }

    pub(super) fn draw_scenery(
        &self,
        t: f64,
        v: f64,
        dismissal: f64,
        layout: &Layout,
        scenery: &mut Canvas,
    ) -> [f64; 4] {
        scenery.0.clear();
        let active = t < self.duration();
        if let Self::Rain(r) = self {
            return r.draw(t, active, scenery);
        }
        if matches!(self, Self::Flyover) {
            if active && t > 0. {
                flyover::scenery(
                    scenery,
                    (layout.width + 26.) * t / self.duration() - layout.anchor_x,
                );
            }
            return [1.; 4];
        }
        let room = layout.width - layout.anchor_x;
        if active {
            scenery.opacity(1. - dismissal);
            match self {
                Self::Sunrise => sunrise::scenery(scenery, t, v, room),
                Self::BridgeLift => bridge_lift::scenery(scenery, t, v),
                Self::TurningTide { rising } => {
                    turning_tide::draw(scenery, false, t, v, room, *rising)
                }
                Self::LastTrain { destination, time } => {
                    last_train::scenery(scenery, t, v, destination, time)
                }
                _ => unreachable!(),
            }
        }
        let [a, b, c] = self.cues().unwrap();
        [
            1.,
            eased(t, a, a + 0.42),
            eased(t, b, b + 0.42),
            eased(t, c, c + 0.42),
        ]
    }
}

// SplitMix64. The upper 53 bits give a reproducible sample in [0, 1).
pub(crate) struct Samples(pub(crate) u64);

impl Samples {
    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9e3779b97f4a7c15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d049bb133111eb);
        z ^ (z >> 31)
    }

    pub(crate) fn range(&mut self, low: f64, high: f64) -> f64 {
        low + (high - low) * ((self.next() >> 11) as f64 / ((1u64 << 53) as f64))
    }
}
