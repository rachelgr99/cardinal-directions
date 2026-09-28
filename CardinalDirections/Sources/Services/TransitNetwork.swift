import CoreLocation
import Foundation

/// The Marguerite network turned into something searchable: stops indexed by
/// id, walking neighbours precomputed, and per-line ride times estimated from
/// the geometry between consecutive stops.
struct TransitNetwork {
    /// One stop occurrence on one line (a line can serve the same stop twice).
    struct LineStop: Hashable {
        let lineID: Int
        let index: Int
    }

    static let walkingSpeed: CLLocationDistance = 1.35 // m/s, brisk campus pace
    static let busSpeed: CLLocationDistance = 7.0 // m/s, ~16 mph door to door
    static let dwellSeconds: TimeInterval = 20
    static let transferWalkRadius: CLLocationDistance = 420
    static let accessWalkRadius: CLLocationDistance = 1_300

    let stops: [Int: Stop]
    let lines: [Int: Line]
    private(set) var shapes: [Int: [CLLocationCoordinate2D]] = [:]
    /// lineID -> ride seconds between stop i and stop i+1
    private(set) var segmentSeconds: [Int: [TimeInterval]] = [:]
    /// stopID -> the line stops boarding there
    private(set) var boardings: [Int: [LineStop]] = [:]
    /// stopID -> nearby stopIDs you can reasonably walk to
    private(set) var walkNeighbors: [Int: [(stopID: Int, seconds: TimeInterval)]] = [:]

    init(lines: [Line], stops: [Stop]) {
        self.stops = Dictionary(stops.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.lines = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for line in lines {
            shapes[line.id] = Polyline.decode(line.encLine)
            var seconds: [TimeInterval] = []
            for index in 0..<max(line.stopIDs.count - 1, 0) {
                seconds.append(Self.rideSeconds(from: line.stopIDs[index], to: line.stopIDs[index + 1], stops: self.stops))
            }
            segmentSeconds[line.id] = seconds
            for (index, stopID) in line.stopIDs.enumerated() {
                boardings[stopID, default: []].append(LineStop(lineID: line.id, index: index))
            }
        }

        let served = boardings.keys.compactMap { self.stops[$0] }
        for stop in served {
            var neighbors: [(Int, TimeInterval)] = []
            for other in served where other.id != stop.id {
                let meters = stop.coordinate.distance(to: other.coordinate)
                if meters <= Self.transferWalkRadius {
                    neighbors.append((other.id, meters / Self.walkingSpeed))
                }
            }
            walkNeighbors[stop.id] = neighbors.sorted { $0.1 < $1.1 }.prefix(6).map { (stopID: $0.0, seconds: $0.1) }
        }
    }

    var isEmpty: Bool { stops.isEmpty || lines.isEmpty }

    func line(routeID: Int) -> Line? {
        lines.values.first { $0.routes.contains(routeID) }
    }

    func stopsServed() -> [Stop] {
        boardings.keys.compactMap { stops[$0] }
    }

    func nearestStops(to coordinate: CLLocationCoordinate2D, limit: Int = 6, radius: CLLocationDistance = accessWalkRadius) -> [(stop: Stop, meters: CLLocationDistance)] {
        stopsServed()
            .map { (stop: $0, meters: coordinate.distance(to: $0.coordinate)) }
            .filter { $0.meters <= radius }
            .sorted { $0.meters < $1.meters }
            .prefix(limit)
            .map { $0 }
    }

    /// Ride seconds for one hop, from straight-line distance inflated for the
    /// fact that buses follow streets, plus a dwell allowance.
    private static func rideSeconds(from: Int, to: Int, stops: [Int: Stop]) -> TimeInterval {
        guard let a = stops[from], let b = stops[to] else { return 120 }
        let meters = a.coordinate.distance(to: b.coordinate) * 1.25
        return meters / busSpeed + dwellSeconds
    }
}
