#[unsafe(no_mangle)]
pub extern "C" fn avesd_next_click_count(current: u64) -> u64 {
    avesd_core::next_click_count(current)
}

use avesd_core::rain::{RainFrame, RainShower};

#[unsafe(no_mangle)]
pub extern "C" fn avesd_rain_shower(seed: u64) -> RainShower {
    RainShower::new(seed)
}

#[unsafe(no_mangle)]
pub extern "C" fn avesd_rain_frame(
    shower: &RainShower,
    elapsed_ms: f64,
    reduced: bool,
) -> RainFrame {
    shower.frame(elapsed_ms, reduced)
}

mod overlay;
