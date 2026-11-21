#[unsafe(no_mangle)]
pub extern "C" fn avesd_next_click_count(current: u64) -> u64 {
    avesd_core::next_click_count(current)
}
