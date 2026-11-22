use avesd_events::Event;
use serde_json::{Value, json};

#[test]
fn preview_records_round_trip_on_the_wire() {
    for bytes in [
        include_str!("../fixtures/flyover.json"),
        include_str!("../fixtures/rain.json"),
        include_str!("../fixtures/sunrise.json"),
        include_str!("../fixtures/bridge_lift.json"),
        include_str!("../fixtures/turning_tide.json"),
        include_str!("../fixtures/last_train.json"),
    ] {
        let original: Value = serde_json::from_str(bytes).unwrap();
        let mut extended = original.clone();
        extended["future_field"] = json!(true);
        extended["data"]["future_field"] = json!("extra");
        let event: Event = serde_json::from_value(extended).unwrap();
        assert_eq!(serde_json::to_value(event).unwrap(), original);
    }
}
