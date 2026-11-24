use h3o::{CellIndex, LatLng, Resolution};

pub fn is_region(cell: u64) -> bool {
    CellIndex::try_from(cell).is_ok_and(|index| index.resolution() == Resolution::Six)
}

pub fn cell(latitude: f64, longitude: f64) -> Option<u64> {
    if !(-90.0..=90.0).contains(&latitude) || !(-180.0..=180.0).contains(&longitude) {
        return None;
    }
    let point = LatLng::new(latitude, longitude).ok()?;
    Some(point.to_cell(Resolution::Six).into())
}

#[cfg(test)]
mod tests {
    use super::cell;

    #[test]
    fn coordinates_match_the_event_feed_regions() {
        assert_eq!(cell(35.02258, 135.79506), Some(0x862e6140fffffff));
        assert_eq!(cell(37.775, -122.418), Some(0x86283082fffffff));
        assert_eq!(cell(135.79506, 35.02258), None);
    }
}
