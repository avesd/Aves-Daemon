use h3o::{CellIndex, LatLng, Resolution};

/// The v1 aircraft search circle for a canonical resolution-six H3 cell.
pub struct Region {
    center: LatLng,
    radius_m: f64,
}

impl Region {
    pub fn from_id(id: &str) -> Option<Self> {
        let cell: CellIndex = id.parse().ok()?;
        if cell.resolution() != Resolution::Six || cell.to_string() != id {
            return None;
        }
        let center = LatLng::from(cell);
        let cell_radius_m = cell
            .boundary()
            .iter()
            .map(|vertex| center.distance_m(*vertex))
            .fold(0.0, f64::max);
        Some(Self {
            center,
            radius_m: cell_radius_m + 3_000.0,
        })
    }

    pub fn center_degrees(&self) -> (f64, f64) {
        (self.center.lat(), self.center.lng())
    }

    pub fn radius_m(&self) -> f64 {
        self.radius_m
    }

    pub fn distance_m(&self, latitude: f64, longitude: f64) -> f64 {
        LatLng::new(latitude, longitude)
            .map_or(f64::INFINITY, |point| self.center.distance_m(point))
    }

    pub fn contains(&self, latitude: f64, longitude: f64) -> bool {
        if !(-90.0..=90.0).contains(&latitude) || !(-180.0..=180.0).contains(&longitude) {
            return false;
        }
        self.distance_m(latitude, longitude) <= self.radius_m
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_only_canonical_cells_at_the_service_resolution() {
        for id in [
            "86283082FFFFFFF",
            "086283082fffffff",
            "8928308280fffff",
            "garbage",
        ] {
            assert!(Region::from_id(id).is_none());
        }
    }

    #[test]
    fn circle_includes_the_buffer_at_every_boundary_vertex() {
        let hexagon = "86283082fffffff".parse().unwrap();
        let pentagon = Resolution::Six.pentagons().next().unwrap();
        for cell in [hexagon, pentagon] {
            let region = Region::from_id(&cell.to_string()).unwrap();
            let center = LatLng::from(cell);
            for vertex in cell.boundary().iter() {
                assert!(region.radius_m() >= center.distance_m(*vertex) + 3_000.0);
            }
            assert!(region.radius_m() < 10_000.0);
        }
    }
}
