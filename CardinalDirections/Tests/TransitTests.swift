import CoreLocation
import XCTest

@testable import CardinalDirections

final class PolylineTests: XCTestCase {
    func testDecodesGoogleReferencePolyline() {
        let points = Polyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0].latitude, 38.5, accuracy: 0.0001)
        XCTAssertEqual(points[0].longitude, -120.2, accuracy: 0.0001)
        XCTAssertEqual(points[2].latitude, 43.252, accuracy: 0.0001)
        XCTAssertEqual(points[2].longitude, -126.453, accuracy: 0.0001)
    }

    func testDecodesEmptyString() {
        XCTAssertTrue(Polyline.decode("").isEmpty)
    }
}

final class ModelTests: XCTestCase {
    func testStopDisplayNameStripsCodePrefix() {
        let stop = Stop(id: 1, name: "(#103) On Roth Way @ Campus Drive", lat: 37.42, lng: -122.17, shortName: "103")
        XCTAssertEqual(stop.displayName, "On Roth Way @ Campus Drive")
        XCTAssertEqual(stop.code, "103")
    }

    func testLineBadgeAndLoopDetection() {
        let line = Line(
            id: 7,
            name: "Y Line - All Loops",
            color: "#00A79D",
            encLine: "",
            routes: [42],
            routeNames: ["Y Line"],
            stopIDs: [1, 2, 3, 1],
            length: 3.2
        )
        XCTAssertEqual(line.badge, "Y")
        XCTAssertEqual(line.routeID, 42)
        XCTAssertTrue(line.isLoop)
    }

    private func vehicle(nextStopETA: Int) -> Vehicle {
        Vehicle(
            equipmentID: "1234",
            routeID: 42,
            lat: 37.42,
            lng: -122.17,
            h: 90,
            load: 10,
            capacity: 40,
            nextStopID: 2,
            nextStopETA: nextStopETA,
            inService: 1,
            receiveTime: nil
        )
    }

    /// 21:07 local, so a `nextStopETA` of 1269 (21:09) is 2 minutes out.
    private func nineOhSevenPM() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 27
        components.hour = 21
        components.minute = 7
        return Calendar.current.date(from: components)!
    }

    func testVehicleTreatsNegativeETAAsUnknown() {
        let bus = vehicle(nextStopETA: -1)
        XCTAssertNil(bus.minutesToNextStop(now: nineOhSevenPM()))
        XCTAssertTrue(bus.isInService)
        XCTAssertEqual(bus.fullness ?? 0, 0.25, accuracy: 0.001)
    }

    func testNextStopETAIsClockTimeNotCountdown() {
        XCTAssertEqual(vehicle(nextStopETA: 1269).minutesToNextStop(now: nineOhSevenPM()), 2)
        XCTAssertEqual(vehicle(nextStopETA: 1267).minutesToNextStop(now: nineOhSevenPM()), 0)
    }

    func testNextStopETAWrapsPastMidnight() {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 27
        components.hour = 23
        components.minute = 55
        let nearMidnight = Calendar.current.date(from: components)!
        XCTAssertEqual(vehicle(nextStopETA: 5).minutesToNextStop(now: nearMidnight), 10)
    }

    func testStaleNextStopETAIsDiscarded() {
        XCTAssertNil(vehicle(nextStopETA: 600).minutesToNextStop(now: nineOhSevenPM()))
        XCTAssertNil(vehicle(nextStopETA: 2000).minutesToNextStop(now: nineOhSevenPM()))
    }

    func testScheduledArrivalIsNotLive() {
        let scheduled = Arrival(minutes: 12, routeID: 42, stopID: 2, time: nil, direction: nil, equipmentID: "-")
        let live = Arrival(minutes: 3, routeID: 42, stopID: 2, time: nil, direction: nil, equipmentID: "5512")
        XCTAssertFalse(scheduled.isLive)
        XCTAssertTrue(live.isLive)
    }
}

final class TripPlannerTests: XCTestCase {
    /// Four stops in a line ~600 m apart, served end to end by one route.
    private func fixture() -> TransitNetwork {
        let stops = (0..<4).map { index in
            Stop(
                id: index + 1,
                name: "(#\(index + 1)) Stop \(index + 1)",
                lat: 37.42,
                lng: -122.18 + Double(index) * 0.0068,
                shortName: "\(index + 1)"
            )
        }
        let line = Line(
            id: 1,
            name: "X Line",
            color: "#8C1515",
            encLine: "",
            routes: [11],
            routeNames: ["X Line"],
            stopIDs: [1, 2, 3, 4],
            length: 2
        )
        return TransitNetwork(lines: [line], stops: stops)
    }

    func testNetworkIndexesBoardingsAndSegments() {
        let network = fixture()
        XCTAssertEqual(network.stopsServed().count, 4)
        XCTAssertEqual(network.segmentSeconds[1]?.count, 3)
        XCTAssertEqual(network.boardings[1]?.count, 1)
        XCTAssertNotNil(network.line(routeID: 11))
        XCTAssertFalse(network.isEmpty)
    }

    func testNearestStopsAreSortedByDistance() {
        let network = fixture()
        let near = network.nearestStops(to: CLLocationCoordinate2D(latitude: 37.4201, longitude: -122.1801), limit: 2)
        XCTAssertEqual(near.first?.stop.id, 1)
        XCTAssertLessThanOrEqual(near[0].meters, near[1].meters)
    }

    func testPlanRidesTheLineEndToEnd() {
        let planner = TripPlanner(network: fixture())
        let origin = Place(name: "start", coordinate: CLLocationCoordinate2D(latitude: 37.4202, longitude: -122.1800))
        let destination = Place(name: "end", coordinate: CLLocationCoordinate2D(latitude: 37.4202, longitude: -122.1596))
        let plans = planner.plans(through: [origin, destination])

        XCTAssertFalse(plans.isEmpty)
        let ride = plans.first(where: { !$0.isWalkOnly })
        XCTAssertNotNil(ride)
        XCTAssertEqual(ride?.rideLines.first?.id, 1)
        XCTAssertEqual(ride?.transfers, 0)
        XCTAssertEqual(plans, plans.sorted { $0.totalSeconds < $1.totalSeconds })
    }

    func testLiveETAOverridesDefaultWait() {
        let planner = TripPlanner(network: fixture())
        let origin = Place(name: "start", coordinate: CLLocationCoordinate2D(latitude: 37.4202, longitude: -122.1800))
        let destination = Place(name: "end", coordinate: CLLocationCoordinate2D(latitude: 37.4202, longitude: -122.1596))

        let planned = planner.plans(through: [origin, destination], liveWaits: [1: [11: 1]])
        let ride = planned.first(where: { !$0.isWalkOnly })
        XCTAssertEqual(ride?.legs.first(where: { $0.kind == .ride })?.waitIsLive, true)
        XCTAssertEqual(ride?.legs.first(where: { $0.kind == .ride })?.waitMinutes, 1)
    }

    func testMultiStopTripVisitsWaypointsInOrder() {
        let planner = TripPlanner(network: fixture())
        let places = [
            Place(name: "start", coordinate: CLLocationCoordinate2D(latitude: 37.4202, longitude: -122.1800)),
            Place(name: "middle", coordinate: CLLocationCoordinate2D(latitude: 37.4202, longitude: -122.1664)),
            Place(name: "end", coordinate: CLLocationCoordinate2D(latitude: 37.4202, longitude: -122.1596))
        ]
        let plans = planner.plans(through: places)
        XCTAssertFalse(plans.isEmpty)
        XCTAssertEqual(plans.first?.legs.first?.fromName, "start")
        XCTAssertEqual(plans.first?.legs.last?.toName, "end")
    }

    func testDormantLinesAreDeprioritisedAgainstRunningOnes() {
        let origin = Place(name: "start", coordinate: CLLocationCoordinate2D(latitude: 37.4202, longitude: -122.1800))
        let destination = Place(name: "end", coordinate: CLLocationCoordinate2D(latitude: 37.4202, longitude: -122.1596))

        // Route 11 has no bus out, and route 99 is the only one running, so the
        // line nobody is driving should look far more expensive than before.
        let optimistic = TripPlanner(network: fixture())
        let realistic = TripPlanner(network: fixture(), runningRouteIDs: [99])

        XCTAssertEqual(optimistic.plans(through: [origin, destination]).first?.isWalkOnly, false)
        XCTAssertEqual(realistic.plans(through: [origin, destination]).first?.isWalkOnly, true)
    }

    func testLiveETABeatsTheDormantPenalty() {
        let planner = TripPlanner(network: fixture(), runningRouteIDs: [99])
        let origin = Place(name: "start", coordinate: CLLocationCoordinate2D(latitude: 37.4202, longitude: -122.1800))
        let destination = Place(name: "end", coordinate: CLLocationCoordinate2D(latitude: 37.4202, longitude: -122.1596))
        let plan = planner.plans(through: [origin, destination], liveWaits: [1: [11: 3]]).first(where: { !$0.isWalkOnly })
        XCTAssertEqual(plan?.legs.first(where: { $0.kind == .ride })?.waitMinutes, 3)
    }

    func testTwoPlacesAreRequired() {
        let planner = TripPlanner(network: fixture())
        XCTAssertTrue(planner.plans(through: [Place(name: "only", coordinate: .init(latitude: 37.42, longitude: -122.17))]).isEmpty)
    }
}

extension TripPlan: Equatable {
    public static func == (a: TripPlan, b: TripPlan) -> Bool { a.id == b.id }
}
