import SwiftUI

@main
struct CardinalDirectionsApp: App {
    @State private var store = TransitStore()
    @State private var location = LocationProvider()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .environment(location)
                .preferredColorScheme(.dark)
                .tint(Palette.hotRed)
        }
    }
}
