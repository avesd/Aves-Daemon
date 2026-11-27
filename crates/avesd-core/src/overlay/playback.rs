use super::{
    content::Content,
    effects::{Effect, Layout},
    frame::{Canvas, eased},
};
use avesd_events::Event;

const HOVER_DWELL: f64 = 0.15;
const OPEN_DURATION: f64 = 0.46;
const SCENERY_CLEARED: f64 = 0.30;
const RECOVERY_DURATION: f64 = 0.20;
const REPLACEMENT_DURATION: f64 = 0.16;

#[derive(Clone, Copy, Default, Debug, PartialEq)]
#[repr(C)]
pub struct Panel {
    pub progress: f64,
    pub expansion: f64,
    pub opacity: f64,
    pub open_fraction: f64,
    pub surface_opacity: f64,
    pub traced_fraction: f64,
    pub trace_opacity: f64,
    pub reveal_edge: f64,
    pub fields: [f64; 4],
    pub alive: bool,
    pub animating: bool,
}

#[repr(C)]
#[derive(Default)]
pub struct FrameChanges {
    pub panel: bool,
    pub icon: bool,
    pub scenery: bool,
}

impl FrameChanges {
    pub fn any(&self) -> bool {
        self.panel || self.icon || self.scenery
    }
}

#[derive(Clone, Copy)]
enum Fade {
    Timed,
    Recover { since: f64, from: f64 },
    Replace { since: f64, from: f64 },
}

pub struct Playback {
    effect: Effect,
    reduced: bool,
    variation: f64,
    remaining: f64,
    fade_duration: f64,
    fade: Fade,
    hover_since: Option<f64>,
    reading: f64,
    last_elapsed: f64,
    layout: Layout,
    pub icon: Canvas,
    pub scenery: Canvas,
    pub panel: Panel,
    sampled: Canvas,
}
impl Playback {
    pub fn new(
        event: &Event,
        content: &Content<'_>,
        seed: u64,
        reduced: bool,
        hold_ms: f64,
        layout: Layout,
    ) -> Self {
        let mut random = super::effects::Samples(seed);
        let mut session = Self {
            effect: Effect::new(&event.payload, seed, &content.timetable),
            reduced,
            variation: random.range(-1., 1.),
            remaining: hold_ms / 1000.,
            fade_duration: (hold_ms / 1000.).min(0.5),
            fade: Fade::Timed,
            hover_since: None,
            reading: 0.,
            last_elapsed: 0.,
            layout,
            sampled: Canvas::default(),
            icon: Canvas::default(),
            scenery: Canvas::default(),
            panel: Panel {
                progress: -1.,
                opacity: 1.,
                alive: true,
                ..Panel::default()
            },
        };
        session.advance(0., false);
        session
    }
    /// Elapsed time is monotonic milliseconds since the preview opened.
    pub fn advance(&mut self, elapsed_ms: f64, inside: bool) -> bool {
        self.advance_changes(elapsed_ms, inside).any()
    }

    /// Retire the displayed frame once, even if several events arrive during the fade.
    pub fn begin_replacement(&mut self, elapsed_ms: f64) {
        if self.panel.alive && elapsed_ms.is_finite() && !matches!(self.fade, Fade::Replace { .. })
        {
            self.fade = Fade::Replace {
                since: (elapsed_ms / 1000.).max(self.last_elapsed),
                from: self.panel.opacity,
            };
        }
    }

    fn advance_hover(&mut self, elapsed: f64, previous: f64, inside: bool) {
        if !inside {
            self.hover_since = None;
            self.panel.expansion = if self.reduced {
                0.
            } else {
                (self.panel.expansion - (elapsed - previous) / 0.368).max(0.)
            };
            return;
        }
        if self.remaining < self.fade_duration {
            self.fade = Fade::Recover {
                since: elapsed,
                from: self.panel.opacity,
            };
        }
        self.remaining = self.remaining.max(1.2);
        let entered = *self.hover_since.get_or_insert(elapsed);
        let opens_at = if self.panel.expansion > 0. {
            previous
        } else {
            previous.max(entered + HOVER_DWELL)
        };
        if elapsed >= opens_at {
            self.panel.expansion = if self.reduced {
                1.
            } else {
                (self.panel.expansion + (elapsed - opens_at) / OPEN_DURATION).min(1.)
            };
        }
    }

    fn advance_visibility(&mut self, elapsed: f64, previous: f64, inside: bool, settled_at: f64) {
        let replacing = matches!(self.fade, Fade::Replace { .. });
        if !replacing {
            self.advance_hover(elapsed, previous, inside);
            // A deliberate hover commits the summary, even if the details close halfway through.
            self.reading = if self.reading > 0. {
                (self.reading + (elapsed - previous) / OPEN_DURATION).min(1.)
            } else {
                self.panel.expansion
            };
        }
        if !inside || replacing {
            self.remaining -= (elapsed - previous.max(settled_at)).max(0.);
        }
        let timed = (self.remaining / self.fade_duration).clamp(0., 1.);
        self.panel.opacity = match self.fade {
            Fade::Timed => timed,
            Fade::Recover { since, from } => {
                let progress = eased(elapsed - since, 0., RECOVERY_DURATION);
                if progress >= 1. {
                    self.fade = Fade::Timed;
                }
                timed.min(from + (1. - from) * progress)
            }
            Fade::Replace { since, from } => {
                timed.min(from * (1. - eased(elapsed - since, 0., REPLACEMENT_DURATION)))
            }
        };
        self.panel.alive = self.remaining > 0. && !(replacing && self.panel.opacity <= 0.);
    }

    pub fn advance_changes(&mut self, elapsed_ms: f64, inside: bool) -> FrameChanges {
        let mut changes = FrameChanges::default();
        if !self.panel.alive || !elapsed_ms.is_finite() {
            return changes;
        }
        let elapsed = (elapsed_ms / 1000.).max(self.last_elapsed);
        let previous = self.last_elapsed;
        self.last_elapsed = elapsed;
        let old = self.panel;
        let duration = self.effect.duration();
        let t = if self.reduced {
            duration
        } else {
            elapsed.min(duration)
        };
        let previous_reading = self.reading;
        self.advance_visibility(
            elapsed,
            previous,
            inside,
            if self.reduced { 0. } else { duration },
        );
        let panel = &mut self.panel;
        panel.progress = t / duration;
        panel.open_fraction = eased(panel.expansion, 0.10, 0.95);
        panel.surface_opacity = eased(panel.expansion, 0.12, 0.96);
        panel.traced_fraction = eased(panel.expansion, 0., 0.86);
        panel.trace_opacity = 0.9 * (1. - eased(panel.expansion, 0.76, 1.));
        let edge = self.effect.reveal_edge(self.layout.width, panel.progress);
        let reveal = eased(self.reading, SCENERY_CLEARED, 0.76);
        panel.reveal_edge = edge + (self.layout.width - edge) * reveal;
        panel.animating = panel.alive
            && (t < duration
                || (panel.expansion < 1. && (inside || panel.expansion > 0.))
                || !matches!(self.fade, Fade::Timed)
                || panel.opacity < 1.);
        let time_changed = panel.progress != old.progress;
        if time_changed && (old.progress < 0. || !matches!(self.effect, Effect::BridgeLift)) {
            self.effect
                .draw_icon(t, self.variation, &self.layout, &mut self.sampled);
            changes.icon = self.icon.replace_if_changed(&mut self.sampled);
        }
        if time_changed || (t < duration && previous_reading != self.reading) {
            panel.fields = self
                .effect
                .draw_scenery(
                    t,
                    self.variation,
                    eased(self.reading, 0., SCENERY_CLEARED),
                    &self.layout,
                    &mut self.sampled,
                )
                .map(|opacity| opacity + (1. - opacity) * reveal);
            changes.scenery = self.scenery.replace_if_changed(&mut self.sampled);
        }
        changes.panel = *panel != old;
        changes
    }
}
