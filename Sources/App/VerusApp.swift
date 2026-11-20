import SwiftUI

@main
struct VerusApp: App {
    @State private var weight = WeightStore()
    @State private var activity = ActivityStore()

    var body: some Scene {
        WindowGroup {
            RootView(weight: weight, activity: activity)
        }
    }
}

/// Three of the concept's five screens exist or are stubbed. Food, Activity
/// and Progress arrive as their own tabs; the tab bar is here now so adding
/// one is a case and not a restructure.
struct RootView: View {
    @Bindable var weight: WeightStore
    @Bindable var activity: ActivityStore

    var body: some View {
        TabView {
            Tab("Home", systemImage: "square.grid.3x3") {
                HomeView(weight: weight, activity: activity)
            }
            Tab("Activity", systemImage: "figure.walk") {
                ActivityView(activity: activity)
            }
            Tab("Weight", systemImage: "scalemass") {
                WeightView(store: weight)
            }
        }
    }
}
