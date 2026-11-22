use chrono_tz::Tz;
use std::sync::LazyLock;

pub struct Location<'a> {
    pub key: &'a str,
    pub name: String,
    pub lat: f64,
    pub lon: f64,
    pub zone: Tz,
}

pub static PLACES: LazyLock<Vec<Location<'static>>> = LazyLock::new(|| {
    include_str!("../../data/places.tsv")
        .lines()
        .filter(|line| !line.starts_with('#'))
        .map(|line| {
            let mut fields = line.split('\t');
            let key = fields.next().unwrap();
            Location {
                key,
                name: key.rsplit('/').next().unwrap().replace('_', " "),
                lat: fields.next().unwrap().parse().unwrap(),
                lon: fields.next().unwrap().parse().unwrap(),
                zone: key.parse().expect("catalog timezone"),
            }
        })
        .collect()
});
