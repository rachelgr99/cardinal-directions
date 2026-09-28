import MapKit
import Observation

/// Address / point-of-interest search around campus, used by the trip planner
/// alongside the Marguerite stop list.
@MainActor
@Observable
final class PlaceSearchService {
    private static let campusRegion = MKCoordinateRegion(
        center: LocationProvider.campusCenter,
        latitudinalMeters: 14_000,
        longitudinalMeters: 14_000
    )

    private var task: Task<Void, Never>?

    var results: [Place] = []
    var isSearching = false

    func search(_ query: String) {
        task?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled, let self else { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmed
            request.region = Self.campusRegion
            let response = try? await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }
            self.results = (response?.mapItems ?? []).prefix(8).map { item in
                Place(
                    name: item.name ?? "Dropped pin",
                    subtitle: item.placemark.title,
                    coordinate: item.placemark.coordinate
                )
            }
            self.isSearching = false
        }
    }

    func clear() {
        task?.cancel()
        results = []
        isSearching = false
    }
}
