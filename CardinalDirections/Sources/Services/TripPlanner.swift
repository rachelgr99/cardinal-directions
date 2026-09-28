import CoreLocation
import Foundation

/// A named point a trip starts at, passes through, or ends at.
struct Place: Identifiable, Hashable {
    let id: UUID
    var name: String
    var subtitle: String?
    var coordinate: CLLocationCoordinate2D
    var isUserLocation: Bool

    init(id: UUID = UUID(), name: String, subtitle: String? = nil, coordinate: CLLocationCoordinate2D, isUserLocation: Bool = false) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.coordinate = coordinate
        self.isUserLocation = isUserLocation
    }

    static func == (a: Place, b: Place) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct Leg: Identifiable {
    enum Kind { case walk, ride }

    let id = UUID()
    let kind: Kind
    let line: Line?
    let fromName: String
    let toName: String
    let seconds: TimeInterval
    let waitSeconds: TimeInterval
    let waitIsLive: Bool
    let stops: [Stop]
    let path: [CLLocationCoordinate2D]

    var totalSeconds: TimeInterval { seconds + waitSeconds }
    var minutes: Int { max(1, Int((seconds / 60).rounded())) }
    var waitMinutes: Int { Int((waitSeconds / 60).rounded()) }
}

struct TripPlan: Identifiable {
    let id = UUID()
    let legs: [Leg]

    var totalSeconds: TimeInterval { legs.reduce(0) { $0 + $1.totalSeconds } }
    var totalMinutes: Int { max(1, Int((totalSeconds / 60).rounded())) }
    var arrival: Date { Date().addingTimeInterval(totalSeconds) }
    var rideLines: [Line] { legs.compactMap(\.line) }
    var transfers: Int { max(0, rideLines.count - 1) }
    var isWalkOnly: Bool { rideLines.isEmpty }
    var walkingMinutes: Int {
        Int((legs.filter { $0.kind == .walk }.reduce(0) { $0 + $1.seconds } / 60).rounded())
    }

    var signature: String { legs.compactMap { $0.line?.id }.map(String.init).joined(separator: "-") }
}

/// Time-dependent-ish trip search over the Marguerite network: a Dijkstra on a
/// graph of stops, boardings, and short walking transfers. Waiting time uses
/// real ETAs where the live feed has them and a headway estimate elsewhere.
struct TripPlanner {
    /// stopID -> routeID -> minutes until the next bus.
    typealias LiveWaits = [Int: [Int: Int]]

    static let defaultWaitSeconds: TimeInterval = 8 * 60
    /// What a line with no live ETA and no bus out there is worth waiting for:
    /// long enough that a running line always wins, short enough that an
    /// otherwise unreachable destination still gets a plan.
    static let dormantWaitSeconds: TimeInterval = 45 * 60
    static let boardPenaltySeconds: TimeInterval = 150
    static let alightSeconds: TimeInterval = 30
    static let transferWalkPenalty: TimeInterval = 30

    let network: TransitNetwork
    /// Route ids with a bus in service right now. Empty means "unknown", and
    /// every line is treated as plausible.
    var runningRouteIDs: Set<Int> = []

    private enum Node: Hashable {
        case origin
        case stop(Int)
        case onboard(TransitNetwork.LineStop)
        case destination
    }

    /// Plans a journey through every waypoint in order and returns a handful of
    /// distinct options, quickest first.
    func plans(through places: [Place], liveWaits: LiveWaits = [:], maxOptions: Int = 3) -> [TripPlan] {
        guard places.count >= 2 else { return [] }
        var options: [TripPlan] = []
        var banned: Set<Int> = []

        for _ in 0..<maxOptions {
            var legs: [Leg] = []
            var failed = false
            for index in 0..<(places.count - 1) {
                guard let hop = search(from: places[index], to: places[index + 1], liveWaits: liveWaits, banned: banned) else {
                    failed = true
                    break
                }
                legs.append(contentsOf: hop)
            }
            guard !failed else { break }
            let plan = TripPlan(legs: legs)
            if options.contains(where: { $0.signature == plan.signature }) { break }
            options.append(plan)
            guard let busiest = plan.legs
                .filter({ $0.kind == .ride })
                .max(by: { $0.seconds < $1.seconds })?.line?.id
            else { break }
            banned.insert(busiest)
        }

        if let walking = walkOnly(through: places),
           !options.contains(where: { $0.isWalkOnly }),
           walking.totalSeconds < 32 * 60 {
            options.append(walking)
        }
        return options.sorted { $0.totalSeconds < $1.totalSeconds }
    }

    func walkOnly(through places: [Place]) -> TripPlan? {
        guard places.count >= 2 else { return nil }
        var legs: [Leg] = []
        for index in 0..<(places.count - 1) {
            let a = places[index]
            let b = places[index + 1]
            let meters = a.coordinate.distance(to: b.coordinate)
            legs.append(
                Leg(
                    kind: .walk,
                    line: nil,
                    fromName: a.name,
                    toName: b.name,
                    seconds: meters / TransitNetwork.walkingSpeed,
                    waitSeconds: 0,
                    waitIsLive: false,
                    stops: [],
                    path: [a.coordinate, b.coordinate]
                )
            )
        }
        return TripPlan(legs: legs)
    }

    // MARK: - Search

    private func search(from origin: Place, to destination: Place, liveWaits: LiveWaits, banned: Set<Int>) -> [Leg]? {
        let accessStops = network.nearestStops(to: origin.coordinate, limit: 8)
        let egressStops = network.nearestStops(to: destination.coordinate, limit: 8)
        guard !accessStops.isEmpty, !egressStops.isEmpty else { return nil }
        let egressByID = Dictionary(egressStops.map { ($0.stop.id, $0.meters) }, uniquingKeysWith: { a, _ in a })

        var best: [Node: TimeInterval] = [.origin: 0]
        var cameFrom: [Node: Node] = [:]
        var visited: Set<Node> = []
        var queue = PriorityQueue<Node>()
        queue.push(.origin, priority: 0)

        while let (node, cost) = queue.pop() {
            if visited.contains(node) { continue }
            visited.insert(node)
            if node == .destination { break }

            for (next, edge) in edges(from: node, origin: origin, accessStops: accessStops, egressByID: egressByID, liveWaits: liveWaits, banned: banned) {
                let candidate = cost + edge
                if candidate < best[next] ?? .infinity {
                    best[next] = candidate
                    cameFrom[next] = node
                    queue.push(next, priority: candidate)
                }
            }
        }

        guard best[.destination] != nil else { return nil }

        var chain: [Node] = [.destination]
        while let previous = cameFrom[chain.last!] {
            chain.append(previous)
            if previous == .origin { break }
        }
        return legs(for: Array(chain.reversed()), origin: origin, destination: destination, liveWaits: liveWaits)
    }

    private func edges(
        from node: Node,
        origin: Place,
        accessStops: [(stop: Stop, meters: CLLocationDistance)],
        egressByID: [Int: CLLocationDistance],
        liveWaits: LiveWaits,
        banned: Set<Int>
    ) -> [(Node, TimeInterval)] {
        switch node {
        case .origin:
            return accessStops.map { (.stop($0.stop.id), $0.meters / TransitNetwork.walkingSpeed) }

        case .destination:
            return []

        case let .stop(stopID):
            var result: [(Node, TimeInterval)] = []
            if let meters = egressByID[stopID] {
                result.append((.destination, meters / TransitNetwork.walkingSpeed))
            }
            for boarding in network.boardings[stopID] ?? [] where !banned.contains(boarding.lineID) {
                let wait = waitSeconds(stopID: stopID, lineID: boarding.lineID, liveWaits: liveWaits).seconds
                result.append((.onboard(boarding), wait + Self.boardPenaltySeconds))
            }
            for neighbor in network.walkNeighbors[stopID] ?? [] {
                result.append((.stop(neighbor.stopID), neighbor.seconds + Self.transferWalkPenalty))
            }
            return result

        case let .onboard(boarding):
            var result: [(Node, TimeInterval)] = []
            guard let line = network.lines[boarding.lineID] else { return result }
            result.append((.stop(line.stopIDs[boarding.index]), Self.alightSeconds))
            if let next = nextIndex(on: line, after: boarding.index) {
                result.append((.onboard(TransitNetwork.LineStop(lineID: line.id, index: next)), hopSeconds(on: line, at: boarding.index)))
            }
            return result
        }
    }

    /// Ride seconds from `index` to the following stop. A loop's wrap-around
    /// hop is free because its first and last stop are the same place.
    private func hopSeconds(on line: Line, at index: Int) -> TimeInterval {
        guard let segments = network.segmentSeconds[line.id], index < segments.count else { return 0 }
        return segments[index]
    }

    private func nextIndex(on line: Line, after index: Int) -> Int? {
        if index + 1 < line.stopIDs.count { return index + 1 }
        return line.isLoop ? 0 : nil
    }

    private func waitSeconds(stopID: Int, lineID: Int, liveWaits: LiveWaits) -> (seconds: TimeInterval, isLive: Bool) {
        guard let line = network.lines[lineID] else { return (Self.defaultWaitSeconds, false) }
        for routeID in line.routes {
            if let minutes = liveWaits[stopID]?[routeID] {
                return (TimeInterval(max(0, minutes) * 60), true)
            }
        }
        if !runningRouteIDs.isEmpty, line.routes.allSatisfy({ !runningRouteIDs.contains($0) }) {
            return (Self.dormantWaitSeconds, false)
        }
        return (Self.defaultWaitSeconds, false)
    }

    // MARK: - Leg reconstruction

    private func legs(for chain: [Node], origin: Place, destination: Place, liveWaits: LiveWaits) -> [Leg] {
        var legs: [Leg] = []
        var index = 0

        func stopName(_ stopID: Int) -> String { network.stops[stopID]?.displayName ?? "stop \(stopID)" }
        func coordinate(_ stopID: Int) -> CLLocationCoordinate2D? { network.stops[stopID]?.coordinate }

        while index < chain.count {
            switch chain[index] {
            case .origin:
                if index + 1 < chain.count, case let .stop(stopID) = chain[index + 1], let target = coordinate(stopID) {
                    let meters = origin.coordinate.distance(to: target)
                    legs.append(walkLeg(from: origin.name, to: stopName(stopID), meters: meters, path: [origin.coordinate, target]))
                }
                index += 1

            case let .stop(stopID):
                if index + 1 < chain.count, case let .stop(nextStopID) = chain[index + 1], let a = coordinate(stopID), let b = coordinate(nextStopID) {
                    legs.append(walkLeg(from: stopName(stopID), to: stopName(nextStopID), meters: a.distance(to: b), path: [a, b]))
                } else if index + 1 < chain.count, chain[index + 1] == .destination, let a = coordinate(stopID) {
                    legs.append(walkLeg(from: stopName(stopID), to: destination.name, meters: a.distance(to: destination.coordinate), path: [a, destination.coordinate]))
                }
                index += 1

            case let .onboard(first):
                var ridden: [TransitNetwork.LineStop] = [first]
                var cursor = index + 1
                while cursor < chain.count, case let .onboard(next) = chain[cursor], next.lineID == first.lineID {
                    ridden.append(next)
                    cursor += 1
                }
                if let leg = rideLeg(ridden, liveWaits: liveWaits) { legs.append(leg) }
                index = cursor

            case .destination:
                index += 1
            }
        }
        return legs
    }

    private func walkLeg(from: String, to: String, meters: CLLocationDistance, path: [CLLocationCoordinate2D]) -> Leg {
        Leg(
            kind: .walk,
            line: nil,
            fromName: from,
            toName: to,
            seconds: meters / TransitNetwork.walkingSpeed,
            waitSeconds: 0,
            waitIsLive: false,
            stops: [],
            path: path
        )
    }

    private func rideLeg(_ ridden: [TransitNetwork.LineStop], liveWaits: LiveWaits) -> Leg? {
        guard let first = ridden.first, let last = ridden.last, let line = network.lines[first.lineID] else { return nil }
        let stopIDs = ridden.map { line.stopIDs[$0.index] }
        let stops = stopIDs.compactMap { network.stops[$0] }
        guard let boardStop = stops.first, let alightStop = stops.last else { return nil }

        var seconds: TimeInterval = 0
        var cursor = first.index
        var guardRail = 0
        while cursor != last.index, guardRail < line.stopIDs.count + 1 {
            seconds += hopSeconds(on: line, at: cursor)
            cursor = nextIndex(on: line, after: cursor) ?? last.index
            guardRail += 1
        }
        let wait = waitSeconds(stopID: boardStop.id, lineID: line.id, liveWaits: liveWaits)

        return Leg(
            kind: .ride,
            line: line,
            fromName: boardStop.displayName,
            toName: alightStop.displayName,
            seconds: seconds,
            waitSeconds: wait.seconds,
            waitIsLive: wait.isLive,
            stops: stops,
            path: stops.map(\.coordinate)
        )
    }
}

/// Minimal binary heap, enough for the Dijkstra above.
struct PriorityQueue<Element: Hashable> {
    private var storage: [(element: Element, priority: Double)] = []

    mutating func push(_ element: Element, priority: Double) {
        storage.append((element, priority))
        var child = storage.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard storage[child].priority < storage[parent].priority else { break }
            storage.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> (Element, Double)? {
        guard !storage.isEmpty else { return nil }
        storage.swapAt(0, storage.count - 1)
        let top = storage.removeLast()
        var parent = 0
        while true {
            let left = parent * 2 + 1
            let right = left + 1
            var smallest = parent
            if left < storage.count, storage[left].priority < storage[smallest].priority { smallest = left }
            if right < storage.count, storage[right].priority < storage[smallest].priority { smallest = right }
            if smallest == parent { break }
            storage.swapAt(parent, smallest)
            parent = smallest
        }
        return (top.element, top.priority)
    }
}
