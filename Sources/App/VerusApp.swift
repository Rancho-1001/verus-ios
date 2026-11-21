import SwiftUI

@main
struct VerusApp: App {
    @State private var weight = WeightStore()
    @State private var activity = ActivityStore()
    @State private var progress = ProgressStore()
    @State private var food = FoodStore()

    var body: some Scene {
        WindowGroup {
            RootView(weight: weight, activity: activity, progress: progress, food: food)
        }
    }
}

/// All five of the concept's screens. Food logs manually today; the
/// photo-to-calorie path is gated on the accuracy spike and the screen says
/// so rather than hiding the gap.
struct RootView: View {
    @Bindable var weight: WeightStore
    @Bindable var activity: ActivityStore
    @Bindable var progress: ProgressStore
    @Bindable var food: FoodStore

    var body: some View {
        TabView {
            Tab("Home", systemImage: "square.grid.3x3") {
                HomeView(weight: weight, activity: activity)
            }
            Tab("Activity", systemImage: "figure.walk") {
                ActivityView(activity: activity)
            }
            Tab("Food", systemImage: "fork.knife") {
                FoodView(food: food, activity: activity, weight: weight)
            }
            Tab("Weight", systemImage: "scalemass") {
                WeightView(store: weight, activity: activity)
            }
            Tab("Progress", systemImage: "photo.on.rectangle.angled") {
                ProgressTimelineView(progress: progress, weight: weight)
            }
        }
    }
}
