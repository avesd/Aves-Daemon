mod bridge_lift;
mod flyover;
mod last_train;
mod note;
pub mod rain;
mod sunrise;
mod turning_tide;

use super::frame::{Canvas, eased};
use avesd_events::{Payload, turning_tide::Turn};
use rain::RainShower;

const SUNRISE_CUES: [f64; 3] = [4.25, 4.50, 4.87];
const BRIDGE_LIFT_CUES: [f64; 3] = [4.81, 5.04, 5.35];
const TURNING_TIDE_CUES: [f64; 3] = [5.35, 5.62, 5.97];
const LAST_TRAIN_CUES: [f64; 3] = [2.72, 2.94, 3.23];
const FIELD_FADE: f64 = 0.42;

pub enum Effect {
    Note,
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
            Payload::Note(_) => Self::Note,
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
            Self::Note => 0.65,
            Self::Flyover => 2.45,
            Self::Rain(r) => r.duration_ms / 1000.,
            Self::Sunrise => 6.1,
            Self::BridgeLift => 5.85,
            Self::TurningTide { .. } => 7.35,
            Self::LastTrain { .. } => 3.95,
        }
    }
    /// When the uninterrupted gesture has revealed its main summary fields.
    pub fn ready(&self) -> f64 {
        let cues = match self {
            Self::Note | Self::Flyover | Self::Rain(_) => return self.duration(),
            Self::Sunrise => SUNRISE_CUES,
            Self::BridgeLift => BRIDGE_LIFT_CUES,
            Self::TurningTide { .. } => TURNING_TIDE_CUES,
            Self::LastTrain { .. } => LAST_TRAIN_CUES,
        };
        cues[1] + FIELD_FADE
    }
    pub(super) fn reveal_edge(&self, width: f64, progress: f64) -> f64 {
        if matches!(self, Self::Flyover) {
            (flyover::center_x(width, progress) - 16.).min(width)
        } else {
            width
        }
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
            Self::Note => note::icon(icon, t),
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
        let visible = active && dismissal < 1.;
        if visible && dismissal > 0. && !matches!(self, Self::Note) {
            scenery.opacity(1. - dismissal);
        }
        let room = layout.width - layout.anchor_x;
        let [a, b, c] = match self {
            Self::Note => return [eased(t, 0., 0.28), eased(t, 0.10, 0.55), 1., 1.],
            Self::Rain(rain) => {
                return if visible {
                    rain.draw(t, active, scenery)
                } else {
                    rain.frame(t * 1000., !active).field_opacity
                };
            }
            Self::Flyover => {
                if visible && t > 0. {
                    flyover::scenery(
                        scenery,
                        flyover::center_x(layout.width, t / self.duration()) - layout.anchor_x,
                    );
                }
                return [1.; 4];
            }
            Self::Sunrise => {
                if visible {
                    sunrise::scenery(scenery, t, v, room);
                }
                SUNRISE_CUES
            }
            Self::BridgeLift => {
                if visible {
                    bridge_lift::scenery(scenery, t, v);
                }
                BRIDGE_LIFT_CUES
            }
            Self::TurningTide { rising } => {
                if visible {
                    turning_tide::draw(scenery, false, t, v, room, *rising);
                }
                TURNING_TIDE_CUES
            }
            Self::LastTrain { destination, time } => {
                if visible {
                    last_train::scenery(scenery, t, v, destination, time);
                }
                LAST_TRAIN_CUES
            }
        };
        [
            eased(t, 0., 0.36),
            eased(t, a, a + FIELD_FADE),
            eased(t, b, b + FIELD_FADE),
            eased(t, c, c + FIELD_FADE),
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
