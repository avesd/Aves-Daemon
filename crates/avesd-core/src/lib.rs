//! Product logic shared by Aves Daemon clients.

pub mod overlay;
pub mod region;
pub use overlay::effects::rain;

pub fn next_click_count(current: u64) -> u64 {
    current.saturating_add(1)
}
