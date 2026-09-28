import CoreLocation
import Foundation

/// A physical Marguerite stop. Mirrors `service=get_stops`.
struct Stop: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let lat: Double
    let lng: Double
    let shortName: String?

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }

    /// Raw names look like `(#103) On Roth Way @ Campus Drive`.
    var displayName: String {
        guard let close = name.firstIndex(of: ")"), name.hasPrefix("(#") else { return name }
        return String(name[name.index(after: close)...]).trimmingCharacters(in: .whitespaces)
    }

    var code: String { shortName ?? String(id) }

    static func == (a: Stop, b: Stop) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A route pattern: the ordered list of stops plus the drawn shape.
/// Mirrors `service=get_patterns`, which (unlike `get_routes`) returns the
/// whole network rather than only the lines running right now.
struct Line: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let color: String
    let encLine: String
    let routes: [Int]
    let routeNames: [String]
    let stopIDs: [Int]
    let length: Double

    /// The id the live vehicle feed and the ETA feed use for this line.
    var routeID: Int { routes.first ?? id }

    /// `C Line` rather than `C Line - All Loops`.
    var shortName: String { routeNames.first ?? name }

    /// `X`, `Y`, `SE`… used for the chunky line badges.
    var badge: String {
        let trimmed = shortName
            .replacingOccurrences(of: " Line", with: "")
            .replacingOccurrences(of: "(Weekday)", with: "")
            .replacingOccurrences(of: "(Weekend)", with: "")
            .trimmingCharacters(in: .whitespaces)
        if trimmed.count <= 4 { return trimmed.uppercased() }
        return trimmed.split(separator: " ").compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    var isLoop: Bool { stopIDs.first == stopIDs.last && stopIDs.count > 2 }

    static func == (a: Line, b: Line) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A live bus. Mirrors `service=get_vehicles`.
struct Vehicle: Codable, Identifiable, Hashable {
    let equipmentID: String
    let routeID: Int
    let lat: Double
    let lng: Double
    let h: Double
    let load: Int?
    let capacity: Int?
    let nextStopID: Int
    let nextStopETA: Int
    let inService: Int
    let receiveTime: Double?

    var id: String { equipmentID }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
    var isInService: Bool { inService == 1 }
    var heading: Double { h }

    /// Minutes until this bus reaches its next stop, when the feed knows.
    ///
    /// The feed reports `nextStopETA` as a clock time — minutes since local
    /// midnight — rather than a countdown, and `-1` when it has no prediction.
    func minutesToNextStop(now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard nextStopETA >= 0, nextStopETA < 24 * 60 else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        var remaining = nextStopETA - nowMinutes
        if remaining < -720 { remaining += 24 * 60 } // prediction lands after midnight
        guard remaining >= -3, remaining <= 120 else { return nil }
        return max(0, remaining)
    }

    /// 0…1 how full the bus is, when the feed reports it.
    var fullness: Double? {
        guard let load, let capacity, capacity > 0, load > 0 else { return nil }
        return min(1, Double(load) / Double(capacity))
    }
}

/// One predicted arrival at a stop. Mirrors an entry of `enRoute` in
/// `service=get_stop_etas`.
struct Arrival: Codable, Identifiable, Hashable {
    let minutes: Int
    let routeID: Int
    let stopID: Int
    let time: String?
    let direction: String?
    let equipmentID: String?

    var id: String { "\(stopID)-\(routeID)-\(minutes)-\(equipmentID ?? "?")" }
    /// The feed sends `-` for scheduled (not yet dispatched) trips.
    var isLive: Bool { (equipmentID ?? "-") != "-" }
}

struct StopArrivals: Codable {
    let id: String
    let enRoute: [Arrival]
}
