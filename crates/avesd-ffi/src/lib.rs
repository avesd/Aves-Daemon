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

#[unsafe(no_mangle)]
pub extern "C" fn avesd_region_cell(latitude: f64, longitude: f64) -> u64 {
    avesd_core::region::cell(latitude, longitude).unwrap_or(0)
}

#[unsafe(no_mangle)]
pub extern "C" fn avesd_region_is_valid(cell: u64) -> bool {
    avesd_core::region::is_region(cell)
}

mod overlay;
