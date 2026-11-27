import AvesdEnvironment
import CAvesdCore
import CoreLocation
import SwiftUI

enum RegionSelection: Codable {
    case kyoto
    case place(name: String, cell: String)
    case device(cell: String, updated: Date)

    enum PollingSelection: Equatable { case device, fixed(String) }

    var pollingSelection: PollingSelection {
        if case .device = self { return .device }
        return .fixed(cell)
    }

    var cell: String {
        switch self {
        case .kyoto: "862e6140fffffff"
        case .place(_, let cell), .device(let cell, _): cell
        }
    }

    var label: String {
        switch self {
        case .kyoto: SettingsText.regionKyoto.string
        case .place(let name, _): name
        case .device: SettingsText.regionDevice.string
        }
    }
}

@MainActor
final class EventRegion: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var selection: RegionSelection
    @Published private(set) var locating = false
    @Published private(set) var message: String?

    private let defaults: UserDefaults
    private let selectionKey = "eventRegion"
    private var manager: CLLocationManager?
    private var awaitingAuthorization = false
    private static let maxAge: TimeInterval = 24 * 60 * 60

    init(defaults: UserDefaults) {
        self.defaults = defaults
        selection = defaults.data(forKey: selectionKey).flatMap {
            try? JSONDecoder().decode(RegionSelection.self, from: $0)
        } ?? .kyoto
        super.init()
    }

    var availableCell: String? {
        if case .device(_, let updated) = selection, locating || Date().timeIntervalSince(updated) >= Self.maxAge { return nil }
        return selection.cell
    }

    func cellAfterRefresh() async -> String? {
        guard locating, !awaitingAuthorization else { return availableCell }
        let (changes, continuation) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let observation = $locating.sink { continuation.yield($0) }
        defer {
            observation.cancel()
            continuation.finish()
        }
        for await inProgress in changes where !inProgress {
            return Task.isCancelled ? nil : availableCell
        }
        return nil
    }

    static func cell(for coordinate: CLLocationCoordinate2D) -> String? {
        let cell = avesd_region_cell(coordinate.latitude, coordinate.longitude)
        return cell == 0 ? nil : String(cell, radix: 16)
    }

    func select(_ selection: RegionSelection) {
        manager?.delegate = nil
        manager?.stopUpdatingLocation()
        manager = nil
        locating = false
        awaitingAuthorization = false
        message = nil
        save(selection)
    }

    private func save(_ selection: RegionSelection) {
        self.selection = selection
        defaults.set(try? JSONEncoder().encode(selection), forKey: selectionKey)
    }

    private func locationManager() -> CLLocationManager {
        if let manager { return manager }
        let manager = CLLocationManager()
        self.manager = manager
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.delegate = self
        return manager
    }

    func useMyLocation() {
        guard !locating else { return }
        let manager = locationManager()
        message = nil
        locating = true
        if manager.authorizationStatus == .notDetermined {
            awaitingAuthorization = true
            manager.requestWhenInUseAuthorization()
        } else {
            requestAuthorizedLocation(manager)
        }
    }

    func refreshIfNeeded(afterWake: Bool = false) {
        guard case .device(_, let updated) = selection, !locating else { return }
        let manager = locationManager()
        guard manager.authorizationStatus == .authorizedAlways else {
            locationAccessUnavailable()
            return
        }
        if afterWake || Date().timeIntervalSince(updated) >= Self.maxAge {
            useMyLocation()
        }
    }

    private func requestAuthorizedLocation(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        } else {
            locationAccessUnavailable()
        }
    }

    private func locationAccessUnavailable() {
        if case .device = selection { select(.kyoto) }
        locating = false
        awaitingAuthorization = false
        message = SettingsText.regionDenied.string
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager === self.manager else { return }
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            locationAccessUnavailable()
        } else if awaitingAuthorization && status != .notDetermined {
            awaitingAuthorization = false
            requestAuthorizedLocation(manager)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard manager === self.manager, locating else { return }
        locating = false
        guard let fix = locations.last, (0...5000).contains(fix.horizontalAccuracy),
              abs(fix.timestamp.timeIntervalSinceNow) <= 300, let cell = Self.cell(for: fix.coordinate) else {
            message = SettingsText.regionImprecise.string
            return
        }
        save(.device(cell: cell, updated: fix.timestamp))
        message = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard manager === self.manager, locating else { return }
        if (error as? CLError)?.code == .denied {
            locationAccessUnavailable()
        } else {
            locating = false
            message = SettingsText.regionFailed.string
        }
    }
}
