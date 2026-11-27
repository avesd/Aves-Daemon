import AvesdEnvironment
import Foundation

struct OverlayContent {
    var icon = "artwork"
    var headline = "", secondary = "", trailing = "", title = "", caption = "", accessibility = ""
    var routeDestination: String?, airlineCode: String?, airlineMark: String?
    var rows: [(label: String, value: String)] = []
}

struct OverlayPresentation: Decodable {
    private let preview: Bool
    private let presentation: Event

    private enum Event: Decodable {
        case flyover(flight: Flight)
        case note(summary: String, detail: String?)
        case observation(place: Place, clock: Clock?, change: Change)
    }

    private struct Flight: Decodable {
        let aircraftId: String
        let origin, destination, originName, destinationName, callsign, aircraftType, model: String?
        let airlineCode, airlineMark, airlineName, flightNumber: String?
    }

    private struct Place: Decodable {
        let place, timeZone: String
        let localName: String?
    }

    private struct Clock: Decodable {
        let timestamp: TimeInterval
        let offsetSeconds: Int
    }

    private enum Intensity: String, Decodable { case none, light, moderate, heavy }
    private enum Trend: String, Decodable { case intensifying, easing, steady }
    private enum Change: Decodable {
        case raining
        case rain(trend: Trend, previous: Intensity, current: Intensity)
        case sunriseSame, sunriseEarlier(minutes: Int), sunriseLater(minutes: Int)
        case bridgeLift(reason: String)
        case highToFalling, lowToRising
        case lastTrain(line: String, destination: String)
    }

    func localized(in bundle: Bundle = CatalogText.bundle, locale: Locale = .current) -> OverlayContent {
        func text(_ message: CatalogText) -> String {
            String(localized: message.resource(in: bundle, locale: locale))
        }
        func intensity(_ value: Intensity) -> String {
            switch value {
            case .none: text(OverlayText.rainIntensityNone)
            case .light: text(OverlayText.rainIntensityLight)
            case .moderate: text(OverlayText.rainIntensityModerate)
            case .heavy: text(OverlayText.rainIntensityHeavy)
            }
        }

        var content = OverlayContent()
        switch presentation {
        case .flyover(let flight):
            content.icon = "airline"
            content.headline = flight.origin ?? flight.callsign ?? flight.aircraftId
            content.routeDestination = flight.destination
            if let callsign = flight.callsign, callsign != content.headline { content.secondary = callsign }
            content.trailing = flight.aircraftType ?? ""
            content.airlineCode = flight.airlineCode ?? "✈"
            content.airlineMark = flight.airlineMark
            content.title = flight.airlineName ?? flight.aircraftId
            content.caption = flight.flightNumber ?? ""
            if let from = flight.originName { content.rows.append((text(OverlayText.flightFrom), from)) }
            if let to = flight.destinationName { content.rows.append((text(OverlayText.flightTo), to)) }
            if let model = flight.model { content.rows.append((text(OverlayText.flightAircraft), model)) }
            var route: String?
            if let from = flight.originName, let to = flight.destinationName {
                route = text(OverlayText.flightSpokenRoute(from, to))
            }
            content.accessibility = [content.title, flight.callsign, route, flight.model]
                .compactMap { $0 }.formatted(.list(type: .and).locale(locale))
        case .note(let summary, let detail):
            content.headline = summary
            content.title = summary
            content.accessibility = summary
            if let detail {
                content.rows = [(text(OverlayText.noteDetail), detail)]
                content.accessibility = text(OverlayText.noteSpoken(summary, detail))
            }
        case .observation(let place, let clock, let change):
            content.headline = place.localName ?? place.place
            content.title = place.place
            if preview { content.caption = text(OverlayText.previewLabel) }
            var label = text(OverlayText.rowEvent)
            let detail: String
            switch change {
            case .raining:
                content.icon = "rain"
                content.secondary = text(OverlayText.rainCurrent)
                detail = text(OverlayText.rainEvent)
            case .rain(let trend, let previous, let current):
                content.icon = "rain"
                switch trend {
                case .intensifying: content.secondary = text(OverlayText.rainIntensifying)
                case .easing: content.secondary = text(OverlayText.rainEasing)
                case .steady: content.secondary = text(OverlayText.rainSteady)
                }
                label = text(OverlayText.rowPrecipitation)
                detail = text(OverlayText.rainTransition(intensity(previous), intensity(current)))
            case .sunriseSame, .sunriseEarlier, .sunriseLater:
                content.secondary = text(OverlayText.sunriseSummary)
                switch change {
                case .sunriseEarlier(let minutes):
                    detail = text(OverlayText.sunriseEarlier(minutes))
                case .sunriseLater(let minutes):
                    detail = text(OverlayText.sunriseLater(minutes))
                default:
                    detail = text(OverlayText.sunriseSame)
                }
            case .bridgeLift(let reason):
                content.secondary = text(OverlayText.bridgeSummary)
                detail = text(OverlayText.bridgeReason(reason))
            case .highToFalling:
                content.secondary = text(OverlayText.tideHighSummary)
                detail = text(OverlayText.tideHighDetail)
            case .lowToRising:
                content.secondary = text(OverlayText.tideLowSummary)
                detail = text(OverlayText.tideLowDetail)
            case .lastTrain(let line, let destination):
                content.secondary = text(OverlayText.trainSummary)
                detail = text(OverlayText.trainDestination(line, destination))
            }
            if let clock {
                let date = Date(timeIntervalSince1970: clock.timestamp)
                let zone = TimeZone(identifier: place.timeZone) ?? TimeZone(secondsFromGMT: clock.offsetSeconds) ?? .gmt
                let style = Date.FormatStyle(locale: locale, timeZone: zone).hour().minute()
                content.trailing = date.formatted(style)
                let time = date.formatted(style.timeZone(.specificName(.short)))
                let timeLabel = place.timeZone == "UTC" ? text(OverlayText.timeUtc) : text(OverlayText.timeLocal)
                content.rows.append((timeLabel, time))
                let description = content.icon == "rain" ? content.secondary : detail
                content.accessibility = text(OverlayText.observationSpoken(place.place, description, time))
            } else {
                content.accessibility = text(OverlayText.rainSpoken(place.place))
            }
            content.rows.append((label, detail))
        }
        if preview { content.accessibility = text(OverlayText.previewSpoken(content.accessibility)) }
        return content
    }
}
