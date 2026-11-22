use super::{
    content::Content,
    effects::{Effect, Layout},
    frame::{Canvas, eased},
};
use avesd_events::Event;

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

pub struct Playback {
    effect: Effect,
    reduced: bool,
    variation: f64,
    remaining: f64,
    hovering: f64,
    dismissal: f64,
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
            effect: Effect::new(&event.payload, seed, &content.trailing),
            reduced,
            variation: random.range(-1., 1.),
            remaining: hold_ms / 1000.,
            hovering: 0.,
            dismissal: 0.,
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

    pub fn advance_changes(&mut self, elapsed_ms: f64, inside: bool) -> FrameChanges {
        let mut changes = FrameChanges::default();
        if !elapsed_ms.is_finite() {
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
            (elapsed - 0.15).clamp(0., duration)
        };
        let panel = &mut self.panel;
        panel.progress = t / duration;
        let previous_dismissal = self.dismissal;
        if t >= self.effect.ready() {
            let ready_at = if self.reduced {
                0.
            } else {
                0.15 + self.effect.ready()
            };
            let delta = (elapsed - previous.max(ready_at)).max(0.);
            if inside {
                self.hovering += delta;
                self.remaining = self.remaining.max(1.2);
            } else {
                self.hovering = 0.;
                if t >= duration {
                    let settled_at = if self.reduced { 0. } else { 0.15 + duration };
                    self.remaining -= (elapsed - previous.max(settled_at)).max(0.);
                }
            }
            if inside && (old.expansion > 0. || self.hovering >= 0.15) {
                let active = if old.expansion > 0. {
                    delta
                } else {
                    delta.min(self.hovering - 0.15)
                };
                panel.expansion = if self.reduced {
                    1.
                } else {
                    (old.expansion + active / 0.46).min(1.)
                };
            } else if !inside {
                panel.expansion = if self.reduced {
                    0.
                } else {
                    (old.expansion - delta / 0.368).max(0.)
                };
            }
            self.dismissal = self.dismissal.max(panel.expansion);
            panel.opacity = (self.remaining / 0.5).clamp(0., 1.);
        }
        panel.open_fraction = eased(panel.expansion, 0.10, 0.95);
        panel.surface_opacity = eased(panel.expansion, 0.12, 0.96);
        panel.traced_fraction = eased(panel.expansion, 0., 0.86);
        panel.trace_opacity = 0.9 * (1. - eased(panel.expansion, 0.76, 1.));
        panel.reveal_edge = if matches!(self.effect, Effect::Flyover) && t < duration {
            (self.layout.width + 26.) * panel.progress - 16.
        } else {
            self.layout.width
        };
        panel.alive = self.remaining > 0.;
        panel.animating =
            t < duration || (panel.expansion > 0. && panel.expansion < 1.) || panel.opacity < 1.;
        let time_changed = panel.progress != old.progress;
        if time_changed && (old.progress < 0. || !matches!(self.effect, Effect::BridgeLift)) {
            self.effect
                .draw_icon(t, self.variation, &self.layout, &mut self.sampled);
            changes.icon = self.icon.replace_if_changed(&mut self.sampled);
        }
        if time_changed || (t < duration && previous_dismissal != self.dismissal) {
            panel.fields = self.effect.draw_scenery(
                t,
                self.variation,
                self.dismissal,
                &self.layout,
                &mut self.sampled,
            );
            changes.scenery = self.scenery.replace_if_changed(&mut self.sampled);
        }
        changes.panel = *panel != old;
        changes
    }
}
