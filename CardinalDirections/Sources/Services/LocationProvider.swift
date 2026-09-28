import CoreLocation
import Observation

/// Thin wrapper over CoreLocation. Falls back to the middle of campus (White
/// Plaza) so the map is never empty while permission is pending.
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    static let campusCenter = CLLocationCoordinate2D(latitude: 37.42452, longitude: -122.17004)

    private let manager = CLLocationManager()

    var coordinate: CLLocationCoordinate2D?
    var authorization: CLAuthorizationStatus = .notDetermined

    /// Where the app should search and plan from right now.
    var effectiveCoordinate: CLLocationCoordinate2D { coordinate ?? Self.campusCenter }
    var hasFix: Bool { coordinate != nil }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
        authorization = manager.authorizationStatus
    }

    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorization == .authorizedWhenInUse || authorization == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        coordinate = last.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
