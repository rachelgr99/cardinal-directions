import SwiftUI

/// Google-Maps-style trip builder: a start, a destination, and as many stops
/// in between as you want — then Marguerite routes generated over the live
/// network.
struct TripPlannerSheet: View {
    @Environment(TransitStore.self) private var store
    @Environment(LocationProvider.self) private var location
    @Environment(\.dismiss) private var dismiss

    @Binding var places: [Place]
    let onSelect: (TripPlan) -> Void

    @State private var editingIndex: Int?

    private var isReady: Bool {
        places.count >= 2 && places.allSatisfy { !$0.name.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                stopsEditor
                actions

                if store.isPlanning {
                    HStack(spacing: 10) {
                        ProgressView().tint(Palette.hotRed)
                        Text("cooking up routes…")
                            .font(.body)
                            .foregroundStyle(Palette.subtext)
                    }
                    .padding(.top, 4)
                }

                if let error = store.planError {
                    Text(error)
                        .font(.body)
                        .foregroundStyle(Palette.poppy)
                }

                if !store.plans.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "your options", trailing: "live ETAs")
                        ForEach(Array(store.plans.enumerated()), id: \.element.id) { index, plan in
                            Button {
                                Haptics.tap()
                                onSelect(plan)
                            } label: {
                                PlanCard(plan: plan, isBest: index == 0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Palette.ink)
        .sheet(item: Binding(get: { editingIndex.map { IndexBox(value: $0) } }, set: { editingIndex = $0?.value })) { box in
            PlaceSearchSheet(title: label(for: box.value)) { picked in
                places[box.value] = picked
                editingIndex = nil
                store.clearPlans()
            }
            .presentationDetents([.large])
            .presentationBackground(Palette.ink)
        }
    }

    private struct IndexBox: Identifiable, Hashable {
        let value: Int
        var id: Int { value }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("plan the move")
                    .font(.display)
                    .foregroundStyle(Palette.text)
                Text("Marguerite only. no car needed 🚌")
                    .font(.caption)
                    .foregroundStyle(Palette.subtext)
            }
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
                    .overlay(Circle().strokeBorder(Palette.hairline))
            }
            .buttonStyle(.plain)
        }
    }

    private var stopsEditor: some View {
        VStack(spacing: 8) {
            ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                HStack(spacing: 10) {
                    marker(for: index)
                    Button {
                        Haptics.tap()
                        editingIndex = index
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name.isEmpty ? label(for: index) : place.name)
                                .font(.rounded(15, .heavy))
                                .foregroundStyle(place.name.isEmpty ? Palette.subtext : Palette.text)
                                .lineLimit(1)
                            if let subtitle = place.subtitle, !place.name.isEmpty {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(Palette.subtext)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .cardSurface(18)
                    }
                    .buttonStyle(.plain)

                    if places.count > 2 && index != 0 && index != places.count - 1 {
                        Button {
                            Haptics.tap()
                            places.remove(at: index)
                            store.clearPlans()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Palette.subtext)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    places.insert(Place(name: "", coordinate: location.effectiveCoordinate), at: max(1, places.count - 1))
                    store.clearPlans()
                } label: {
                    Label("add a stop", systemImage: "plus")
                        .font(.caption)
                        .foregroundStyle(Palette.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Palette.surface))
                        .overlay(Capsule().strokeBorder(Palette.hairline))
                }
                Button {
                    Haptics.tap()
                    places.reverse()
                    store.clearPlans()
                } label: {
                    Label("flip", systemImage: "arrow.up.arrow.down")
                        .font(.caption)
                        .foregroundStyle(Palette.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Palette.surface))
                        .overlay(Capsule().strokeBorder(Palette.hairline))
                }
                Spacer()
            }
            .buttonStyle(.plain)
        }
    }

    private var actions: some View {
        BigButton(title: store.plans.isEmpty ? "find my route" : "re-run it", icon: "bolt.fill") {
            Task { await store.plan(through: places) }
        }
        .opacity(isReady ? 1 : 0.45)
        .disabled(!isReady || store.isPlanning)
    }

    private func marker(for index: Int) -> some View {
        Group {
            if index == 0 {
                Circle().fill(Palette.palo).frame(width: 12, height: 12)
            } else if index == places.count - 1 {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(Palette.illuminating)
            } else {
                Circle().strokeBorder(Palette.poppy, lineWidth: 3).frame(width: 12, height: 12)
            }
        }
        .frame(width: 18)
    }

    private func label(for index: Int) -> String {
        if index == 0 { return "starting point" }
        if index == places.count - 1 { return "where to?" }
        return "stop along the way"
    }
}

struct PlanCard: View {
    let plan: TripPlan
    var isBest: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(plan.totalMinutes)")
                    .font(.displayXL)
                    .foregroundStyle(Palette.text)
                    .monospacedDigit()
                Text("min")
                    .font(.title)
                    .foregroundStyle(Palette.subtext)
                Spacer()
                if isBest {
                    Text("fastest")
                        .font(.micro)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Palette.sunrise))
                }
            }

            // Long multi-stop trips have more hops than fit across the card.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(plan.legs.enumerated()), id: \.element.id) { index, leg in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(Palette.subtext)
                        }
                        if let line = leg.line {
                            LineBadge(line: line, size: 26)
                        } else {
                            Image(systemName: "figure.walk")
                                .font(.system(size: 13, weight: .black))
                                .foregroundStyle(Palette.subtext)
                        }
                    }
                }
                .padding(.vertical, 1)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Pill(text: plan.arrival.formatted(date: .omitted, time: .shortened), icon: "clock.fill")
                    Pill(text: "\(plan.walkingMinutes) min walk", icon: "figure.walk")
                    if plan.transfers > 0 {
                        Pill(text: "\(plan.transfers) transfer\(plan.transfers == 1 ? "" : "s")", icon: "arrow.triangle.swap")
                    }
                }
                .padding(.vertical, 1)
            }

            Text(Copy.planVibe(minutes: plan.totalMinutes, transfers: plan.transfers))
                .font(.caption)
                .foregroundStyle(Palette.poppy)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardSurface(24, highlighted: isBest)
    }
}
