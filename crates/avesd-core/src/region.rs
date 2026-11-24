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
