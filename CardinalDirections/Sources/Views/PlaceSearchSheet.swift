import CoreLocation
import SwiftUI

/// Picker for one end of a trip: your location, a campus favourite, a
/// Marguerite stop, or anything MapKit can find nearby.
struct PlaceSearchSheet: View {
    @Environment(TransitStore.self) private var store
    @Environment(LocationProvider.self) private var location
    @Environment(\.dismiss) private var dismiss

    let title: String
    let onPick: (Place) -> Void

    @State private var query = ""
    @State private var search = PlaceSearchService()
    @FocusState private var focused: Bool

    private static let favourites: [(String, String, CLLocationCoordinate2D)] = [
        ("Tresidder Union", "food + coffee", .init(latitude: 37.42395, longitude: -122.17055)),
        ("Green Library", "lock in 📚", .init(latitude: 37.42690, longitude: -122.16690)),
        ("Palo Alto Caltrain", "get off campus", .init(latitude: 37.44318, longitude: -122.16460)),
        ("Stanford Shopping Center", "retail therapy", .init(latitude: 37.44290, longitude: -122.17170)),
        ("Escondido Village", "grad housing", .init(latitude: 37.42280, longitude: -122.16290)),
        ("Stanford Stadium", "game day 🏈", .init(latitude: 37.43450, longitude: -122.16150))
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.display)
                    .foregroundStyle(Palette.text)
                Spacer()
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Palette.text)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Palette.surface))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Palette.subtext)
                TextField("search stops + places", text: $query)
                    .font(.rounded(16, .semibold))
                    .foregroundStyle(Palette.text)
                    .focused($focused)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button {
                        query = ""
                        search.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.subtext)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .cardSurface(18)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if query.isEmpty {
                        quickPicks
                    }

                    if !search.results.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "places")
                            ForEach(search.results) { place in
                                row(
                                    title: place.name,
                                    subtitle: place.subtitle,
                                    icon: "mappin.circle.fill",
                                    tint: Palette.plum
                                ) { pick(place) }
                            }
                        }
                    }

                    let stops = store.stops(matching: query, near: location.effectiveCoordinate)
                    if !stops.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "marguerite stops")
                            ForEach(stops) { stop in
                                row(
                                    title: stop.displayName,
                                    subtitle: "stop #\(stop.code)",
                                    icon: "bus.fill",
                                    tint: Palette.lagunita
                                ) {
                                    pick(Place(name: stop.displayName, subtitle: "Marguerite stop", coordinate: stop.coordinate))
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .padding(20)
        .background(Palette.ink)
        .onChange(of: query) { _, value in search.search(value) }
        .onAppear { focused = true }
    }

    private var quickPicks: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "quick picks")
            row(title: "My location", subtitle: "where you're standing", icon: "location.fill", tint: Palette.palo) {
                pick(Place(name: "My location", subtitle: "where you're standing", coordinate: location.effectiveCoordinate, isUserLocation: true))
            }
            ForEach(Self.favourites, id: \.0) { favourite in
                row(title: favourite.0, subtitle: favourite.1, icon: "star.fill", tint: Palette.illuminating) {
                    pick(Place(name: favourite.0, subtitle: favourite.1, coordinate: favourite.2))
                }
            }
        }
    }

    private func row(title: String, subtitle: String?, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(tint.opacity(0.16)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.rounded(15, .heavy))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Palette.subtext)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Palette.subtext)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .cardSurface(18)
        }
        .buttonStyle(.plain)
    }

    private func pick(_ place: Place) {
        onPick(place)
        dismiss()
    }
}
