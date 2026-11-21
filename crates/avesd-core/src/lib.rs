//! Product logic shared by Avesd clients and the Worker.

pub fn next_click_count(current: u64) -> u64 {
    current.saturating_add(1)
}
