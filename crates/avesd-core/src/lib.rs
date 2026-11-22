//! Product logic shared by Aves Daemon clients and the Worker.

#[cfg(feature = "overlay")]
pub mod overlay;
#[cfg(feature = "overlay")]
pub use overlay::effects::rain;
pub mod region;

pub fn next_click_count(current: u64) -> u64 {
    current.saturating_add(1)
}
