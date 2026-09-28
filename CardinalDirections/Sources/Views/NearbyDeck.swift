import SwiftUI

/// The Waze-style card that lives at the bottom of the home screen: one big
/// "where to?" tap target, the buses closest to you, and what's coming at the
/// stops you can walk to.
struct NearbyDeck: View {
    @Environment(TransitStore.self) private var store
    @Binding var focusedBus: LiveBus?
    let onPlan: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(Palette.hairline)
                .frame(width: 38, height: 4)
                .padding(.top, 8)

            whereToButton

            switch store.state {
            case .loading:
                loading
            case let .failed(message):
                failure(message)
            case .ready:
                content
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 26)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                .fill(Palette.ink.opacity(0.97))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                        .strokeBorder(Palette.hairline)
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var whereToButton: some View {
        Button {
            Haptics.tap()
            onPlan()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Palette.sunrise))
                Text("where to?")
                    .font(.rounded(19, .black))
                    .foregroundStyle(Palette.text)
                Spacer()
                Text("plan it")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Palette.heat))
            }
            .padding(10)
            .cardSurface(24)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        let buses = store.nearbyBuses(limit: 6)
        let stops = store.nearbyStops(limit: 3)

        if buses.isEmpty && stops.isEmpty {
            Text(Copy.emptyNearby)
                .font(.body)
                .foregroundStyle(Palette.subtext)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "buses near you", trailing: buses.isEmpty ? nil : "\(buses.count) rolling")
                if buses.isEmpty {
                    Text(Copy.emptyNearby)
                        .font(.body)
                        .foregroundStyle(Palette.subtext)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(buses) { bus in
                                BusCard(bus: bus, isFocused: focusedBus?.id == bus.id)
                                    .onTapGesture {
                                        Haptics.tap()
                                        focusedBus = bus
                                    }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollClipDisabled()
                }
            }

            if !stops.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "stops you can walk to")
                    ForEach(stops) { nearby in
                        StopRow(nearby: nearby, line: { store.line(routeID: $0) })
                    }
                }
            }
        }
    }

    private var loading: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Palette.hotRed)
            Text("loading the fleet…")
                .font(.body)
                .foregroundStyle(Palette.subtext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.body)
                .foregroundStyle(Palette.text)
            BigButton(title: "try again", icon: "arrow.clockwise") {
                Task { await store.bootstrap() }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct BusCard: View {
    let bus: LiveBus
    let isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                LineBadge(line: bus.line, size: 30)
                if let minutes = bus.minutes {
                    ETAChip(minutes: minutes, compact: true)
                }
            }
            Text(bus.nextStop?.displayName ?? bus.line.shortName)
                .font(.rounded(13, .semibold))
                .foregroundStyle(Palette.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: 150, alignment: .leading)
            HStack(spacing: 6) {
                Pill(text: "\(Int(bus.meters)) m away", icon: "figure.walk")
                if let fullness = bus.vehicle.fullness, fullness > 0.6 {
                    Pill(text: "packed", icon: "person.3.fill", tint: Palette.poppy)
                }
            }
        }
        .padding(12)
        .cardSurface(22, highlighted: isFocused)
    }
}

private struct StopRow: View {
    let nearby: NearbyStop
    let line: (Int) -> Line?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 2) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 11, weight: .black))
                Text("\(nearby.walkMinutes)m")
                    .font(.micro)
                    .monospacedDigit()
            }
            .foregroundStyle(Palette.subtext)
            .frame(width: 34)

            VStack(alignment: .leading, spacing: 6) {
                Text(nearby.stop.displayName)
                    .font(.rounded(14, .heavy))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                if nearby.arrivals.isEmpty {
                    Text("nothing scheduled rn")
                        .font(.caption)
                        .foregroundStyle(Palette.subtext)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(nearby.arrivals.prefix(4)) { arrival in
                                HStack(spacing: 5) {
                                    if let line = line(arrival.routeID) {
                                        LineBadge(line: line, size: 22)
                                    }
                                    ETAChip(minutes: arrival.minutes, isLive: arrival.isLive, compact: true)
                                }
                                .padding(.trailing, 2)
                            }
                        }
                    }
                    .scrollClipDisabled()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .cardSurface(18)
    }
}
