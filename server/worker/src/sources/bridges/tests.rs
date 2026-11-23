use super::*;
use std::{collections::HashSet, process::Command};

#[test]
fn seaway_keeps_imminent_and_actual_lifts_distinct() {
    let html = r#"<table id="grey_box"><tr><td><span class="lgtextblack">A &amp; B</span>
        <span id="status">Available (raising soon)</span></td></tr></table>
        <table id="grey_box"><tr><td><span class="lgtextblack">C</span>
        <span id="status">Unavailable (raised since 23:58)</span></td></tr></table>"#;
    let rows = seaway::parse("example", html.as_bytes()).unwrap();
    assert_eq!(rows[0].bridge, "A & B");
    assert!(rows[0].raised_since_local.is_none());
    assert_eq!(rows[1].raised_since_local.unwrap().to_string(), "23:58:00");
    assert!(seaway::parse("example", b"<html>maintenance</html>").is_err());
}

/// Exercise the same parsers as the Worker with current public upstream bodies.
#[test]
#[ignore = "requires live network access and curl"]
fn live_bridge_sources() {
    fn fetch(url: &str) -> Vec<u8> {
        let result = Command::new("curl")
            .args([
                "-fsSL",
                "--max-time",
                "15",
                "--max-filesize",
                "8388608",
                url,
            ])
            .output()
            .unwrap();
        assert!(
            result.status.success(),
            "{url}: {}",
            String::from_utf8_lossy(&result.stderr)
        );
        result.stdout
    }
    for (region, url) in seaway::PAGES {
        let rows = seaway::parse(region, &fetch(url)).unwrap();
        println!(
            "Seaway {region}: {} statuses, {} reporting raised since",
            rows.len(),
            rows.iter()
                .filter(|r| r.raised_since_local.is_some())
                .count()
        );
    }
    let lifts = tower::parse(&fetch(tower::URL)).unwrap();
    println!(
        "Tower Bridge: {} scheduled rows, first {:?}",
        lifts.len(),
        lifts.first()
    );
    let history = sdot::parse(&fetch(sdot::URL)).unwrap();
    println!(
        "SDOT: {} completed openings, latest {:?}",
        history.len(),
        history.first()
    );
    let BridgeData::Ndw {
        published_at,
        records,
    } = ndw::parse(&fetch(ndw::URL)).unwrap()
    else {
        unreachable!()
    };
    println!(
        "NDW {published_at}: {} records across {} locations",
        records.len(),
        records
            .iter()
            .map(|r| (&r.location_system, &r.location_code))
            .collect::<HashSet<_>>()
            .len()
    );
}
