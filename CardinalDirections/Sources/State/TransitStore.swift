import CoreLocation
import Observation
import SwiftUI

/// A bus near you, ready to render.
struct LiveBus: Identifiable {
    let vehicle: Vehicle
    let line: Line
    let meters: CLLocationDistance
    let nextStop: Stop?

    var id: String { vehicle.id }
    var minutes: Int? { vehicle.minutesToNextStop() }
}

/// A stop near you plus what's coming.
struct NearbyStop: Identifiable {
    let stop: Stop
    let meters: CLLocationDistance
    let arrivals: [Arrival]

    var id: Int { stop.id }
    var walkMinutes: Int { max(1, Int((meters / TransitNetwork.walkingSpeed / 60).rounded())) }
}

@MainActor
@Observable
final class TransitStore {
    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private let api = MargueriteAPI()
    private var pollTask: Task<Void, Never>?

    var state: LoadState = .loading
    var network: TransitNetwork?
    var vehicles: [Vehicle] = []
    var arrivals: [Int: [Arrival]] = [:]
    var lastUpdated: Date?

    var plans: [TripPlan] = []
    var isPlanning = false
    var planError: String?

    var origin: CLLocationCoordinate2D = LocationProvider.campusCenter

    // MARK: - Loading

    func bootstrap() async {
        if network == nil {
            do {
                async let lines = api.lines()
                async let stops = api.stops()
                network = TransitNetwork(lines: try await lines, stops: try await stops)
                state = .ready
            } catch {
                state = .failed("couldn't reach the Marguerite feed")
                return
            }
        }
        await refresh()
    }

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12))
                guard let self else { return }
                await self.refresh()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        guard let network else { return }
        if let live = try? await api.vehicles() {
            vehicles = live
            lastUpdated = Date()
            if case .failed = state { state = .ready }
        }
        let stopIDs = network.nearestStops(to: origin, limit: 6, radius: 1_600).map(\.stop.id)
        let fetched = await api.arrivals(stopIDs: stopIDs)
        arrivals.merge(fetched) { _, new in new }
        for stopID in stopIDs where fetched[stopID] == nil {
            arrivals[stopID] = []
        }
    }

    // MARK: - Derived

    /// Buses in service, closest first. Falls back to every reporting bus at
    /// night, when nothing is technically "in service" but the map should
    /// still show where the fleet is.
    func nearbyBuses(limit: Int = 8) -> [LiveBus] {
        guard let network else { return [] }
        let inService = vehicles.filter(\.isInService)
        let pool = inService.isEmpty ? vehicles : inService
        return pool.compactMap { vehicle -> LiveBus? in
            guard let line = network.line(routeID: vehicle.routeID) else { return nil }
            return LiveBus(
                vehicle: vehicle,
                line: line,
                meters: origin.distance(to: vehicle.coordinate),
                nextStop: network.stops[vehicle.nextStopID]
            )
        }
        .sorted { $0.meters < $1.meters }
        .prefix(limit)
        .map { $0 }
    }

    func nearbyStops(limit: Int = 5) -> [NearbyStop] {
        guard let network else { return [] }
        return network.nearestStops(to: origin, limit: limit, radius: 1_600).map {
            NearbyStop(stop: $0.stop, meters: $0.meters, arrivals: arrivals[$0.stop.id] ?? [])
        }
    }

    /// Lines worth drawing on the home map: the ones with buses out right now.
    func activeLines() -> [Line] {
        guard let network else { return [] }
        let routeIDs = Set(vehicles.filter(\.isInService).map(\.routeID))
        let lines = routeIDs.compactMap { network.line(routeID: $0) }
        if !lines.isEmpty { return lines }
        // Nothing running: show the lines serving the stops closest to you.
        let nearby = network.nearestStops(to: origin, limit: 4, radius: 1_600)
        let ids = Set(nearby.flatMap { network.boardings[$0.stop.id] ?? [] }.map(\.lineID))
        return ids.compactMap { network.lines[$0] }
    }

    func line(routeID: Int) -> Line? { network?.line(routeID: routeID) }

    func stops(matching query: String, near coordinate: CLLocationCoordinate2D, limit: Int = 12) -> [Stop] {
        guard let network else { return [] }
        let all = network.stopsServed()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let filtered = trimmed.isEmpty
            ? all
            : all.filter { $0.displayName.localizedCaseInsensitiveContains(trimmed) || $0.code.contains(trimmed) }
        return filtered
            .sorted { coordinate.distance(to: $0.coordinate) < coordinate.distance(to: $1.coordinate) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Planning

    func plan(through places: [Place]) async {
        guard let network, places.count >= 2 else { return }
        isPlanning = true
        planError = nil
        defer { isPlanning = false }

        // Real waits matter most where you board, so pull live ETAs for the
        // stops around every waypoint before searching.
        var boardingStops: Set<Int> = []
        for place in places.dropLast() {
            boardingStops.formUnion(network.nearestStops(to: place.coordinate, limit: 6).map(\.stop.id))
        }
        let live = await api.arrivals(stopIDs: Array(boardingStops))
        arrivals.merge(live) { _, new in new }

        var waits: TripPlanner.LiveWaits = [:]
        for (stopID, list) in live {
            for arrival in list where waits[stopID]?[arrival.routeID] == nil {
                waits[stopID, default: [:]][arrival.routeID] = arrival.minutes
            }
        }

        let planner = TripPlanner(
            network: network,
            runningRouteIDs: Set(vehicles.filter(\.isInService).map(\.routeID))
        )
        let results = planner.plans(through: places, liveWaits: waits)
        plans = results
        if results.isEmpty {
            planError = "couldn't find a Marguerite route for that one 😬"
        } else {
            Haptics.pop()
        }
    }

    func clearPlans() {
        plans = []
        planError = nil
    }
}
