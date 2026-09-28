import MapKit
import SwiftUI

struct HomeView: View {
    @Environment(TransitStore.self) private var store
    @Environment(LocationProvider.self) private var location

    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: LocationProvider.campusCenter,
            latitudinalMeters: 2_600,
            longitudinalMeters: 2_600
        )
    )
    @State private var showPlanner = false
    @State private var selectedPlan: TripPlan?
    @State private var planPlaces: [Place] = []
    @State private var focusedBus: LiveBus?

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
                .ignoresSafeArea()

            Palette.glow
                .frame(height: 260)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                TopBar(lastUpdated: store.lastUpdated, isLive: !store.vehicles.isEmpty)
                Spacer(minLength: 0)
            }

            VStack {
                Spacer()
                bottomDeck
            }
        }
        .background(Palette.ink)
        .overlay(alignment: .trailing) { recenterButton }
        .task {
            location.start()
            store.origin = location.effectiveCoordinate
            await store.bootstrap()
            store.startPolling()
        }
        .onDisappear { store.stopPolling() }
        .onChange(of: location.coordinate?.latitude) { _, _ in
            guard let coordinate = location.coordinate else { return }
            store.origin = coordinate
        }
        .sheet(isPresented: $showPlanner) {
            TripPlannerSheet(places: $planPlaces) { plan in
                selectedPlan = plan
                showPlanner = false
                focus(on: plan)
            }
            .presentationDetents([.large])
            .presentationBackground(Palette.ink)
        }
    }

    // MARK: - Map

    private var mapLayer: some View {
        Map(position: $camera) {
            UserAnnotation()

            if let plan = selectedPlan {
                ForEach(plan.legs) { leg in
                    if leg.kind == .ride, let line = leg.line {
                        MapPolyline(coordinates: ridePath(for: leg, line: line))
                            .stroke(Color(hex: line.color).punchy, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    } else {
                        MapPolyline(coordinates: leg.path)
                            .stroke(Palette.text.opacity(0.75), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 9]))
                    }
                }
                ForEach(planMarkers(plan)) { marker in
                    Annotation(marker.title, coordinate: marker.coordinate, anchor: .center) {
                        PlanPin(marker: marker)
                    }
                }
            } else {
                ForEach(store.activeLines()) { line in
                    if let shape = store.network?.shapes[line.id], shape.count > 1 {
                        MapPolyline(coordinates: shape)
                            .stroke(Color(hex: line.color).punchy.opacity(0.55), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }
                }
                ForEach(store.nearbyStops(limit: 8)) { nearby in
                    Annotation(nearby.stop.displayName, coordinate: nearby.stop.coordinate, anchor: .center) {
                        StopPin()
                    }
                    .annotationTitles(.hidden)
                }
            }

            ForEach(store.nearbyBuses(limit: 14)) { bus in
                Annotation(bus.line.shortName, coordinate: bus.vehicle.coordinate, anchor: .center) {
                    BusPin(bus: bus, isFocused: focusedBus?.id == bus.id)
                        .onTapGesture {
                            Haptics.tap()
                            focusedBus = bus
                        }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass() }
    }

    private func ridePath(for leg: Leg, line: Line) -> [CLLocationCoordinate2D] {
        guard let shape = store.network?.shapes[line.id], shape.count > 2,
              let board = leg.stops.first?.coordinate, let alight = leg.stops.last?.coordinate,
              let start = nearestIndex(in: shape, to: board), let end = nearestIndex(in: shape, to: alight)
        else { return leg.path }
        if start <= end { return Array(shape[start...end]) }
        // Loop line that wraps past the end of the shape.
        return Array(shape[start...]) + Array(shape[...end])
    }

    private func nearestIndex(in shape: [CLLocationCoordinate2D], to coordinate: CLLocationCoordinate2D) -> Int? {
        shape.indices.min { shape[$0].distance(to: coordinate) < shape[$1].distance(to: coordinate) }
    }

    private func planMarkers(_ plan: TripPlan) -> [PlanMarker] {
        var markers: [PlanMarker] = []
        for leg in plan.legs where leg.kind == .ride {
            if let board = leg.stops.first {
                markers.append(PlanMarker(title: board.displayName, coordinate: board.coordinate, symbol: "arrow.up", color: Palette.palo))
            }
            if let alight = leg.stops.last {
                markers.append(PlanMarker(title: alight.displayName, coordinate: alight.coordinate, symbol: "arrow.down", color: Palette.hotRed))
            }
        }
        if let last = plan.legs.last?.path.last {
            markers.append(PlanMarker(title: "destination", coordinate: last, symbol: "flag.checkered", color: Palette.illuminating))
        }
        return markers
    }

    // MARK: - Chrome

    private var recenterButton: some View {
        VStack(spacing: 10) {
            Button {
                Haptics.tap()
                withAnimation(.easeInOut) {
                    camera = .region(
                        MKCoordinateRegion(
                            center: location.effectiveCoordinate,
                            latitudinalMeters: 1_400,
                            longitudinalMeters: 1_400
                        )
                    )
                }
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(Palette.text)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Palette.surface.opacity(0.92)))
                    .overlay(Circle().strokeBorder(Palette.hairline))
            }
            if selectedPlan != nil {
                Button {
                    Haptics.tap()
                    selectedPlan = nil
                    store.clearPlans()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(.black)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Palette.illuminating))
                }
            }
        }
        .padding(.trailing, 14)
        .padding(.bottom, 330)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var bottomDeck: some View {
        if let plan = selectedPlan {
            PlanDetailCard(plan: plan) {
                selectedPlan = nil
                showPlanner = true
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            NearbyDeck(
                focusedBus: $focusedBus,
                onPlan: {
                    if planPlaces.isEmpty {
                        planPlaces = [myLocationPlace(), Place(name: "", coordinate: LocationProvider.campusCenter)]
                    }
                    showPlanner = true
                }
            )
        }
    }

    private func myLocationPlace() -> Place {
        Place(name: "My location", subtitle: "where you're standing", coordinate: location.effectiveCoordinate, isUserLocation: true)
    }

    private func focus(on plan: TripPlan) {
        let coordinates = plan.legs.flatMap(\.path)
        guard !coordinates.isEmpty else { return }
        let lats = coordinates.map(\.latitude)
        let lngs = coordinates.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.006, (lats.max()! - lats.min()!) * 1.9),
            longitudeDelta: max(0.006, (lngs.max()! - lngs.min()!) * 1.9)
        )
        withAnimation(.easeInOut) {
            camera = .region(MKCoordinateRegion(center: center, span: span))
        }
    }
}

// MARK: - Map pins

private struct BusPin: View {
    let bus: LiveBus
    let isFocused: Bool

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 5) {
                Text(bus.line.badge)
                    .font(.rounded(12, .black))
                    .foregroundStyle(.black.opacity(0.85))
                if let minutes = bus.minutes {
                    Text(minutes <= 0 ? "now" : "\(minutes)m")
                        .font(.rounded(12, .heavy))
                        .foregroundStyle(.black.opacity(0.7))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color(hex: bus.line.color).punchy)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
            )
            .overlay(
                Capsule().strokeBorder(.white.opacity(isFocused ? 0.95 : 0.25), lineWidth: isFocused ? 2.5 : 1)
            )

            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 8))
                .foregroundStyle(Color(hex: bus.line.color).punchy)
                .offset(y: -2)
        }
        .scaleEffect(isFocused ? 1.12 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isFocused)
    }
}

private struct StopPin: View {
    var body: some View {
        Circle()
            .fill(Palette.text)
            .frame(width: 9, height: 9)
            .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 2))
    }
}

struct PlanMarker: Identifiable {
    let id = UUID()
    let title: String
    let coordinate: CLLocationCoordinate2D
    let symbol: String
    let color: Color
}

private struct PlanPin: View {
    let marker: PlanMarker

    var body: some View {
        Image(systemName: marker.symbol)
            .font(.system(size: 11, weight: .black))
            .foregroundStyle(.black)
            .frame(width: 26, height: 26)
            .background(Circle().fill(marker.color))
            .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 2))
    }
}

// MARK: - Top bar

private struct TopBar: View {
    let lastUpdated: Date?
    let isLive: Bool

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cardinal Directions")
                    .font(.rounded(19, .black))
                    .foregroundStyle(Palette.text)
                Text(Copy.greeting)
                    .font(.caption)
                    .foregroundStyle(Palette.subtext)
            }
            Spacer()
            HStack(spacing: 5) {
                Circle()
                    .fill(isLive ? Palette.palo : Palette.subtext)
                    .frame(width: 7, height: 7)
                    .pulse()
                Text(isLive ? "live" : "…")
                    .font(.micro)
                    .foregroundStyle(Palette.text)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(Palette.surface.opacity(0.9)))
            .overlay(Capsule().strokeBorder(Palette.hairline))
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
    }
}
