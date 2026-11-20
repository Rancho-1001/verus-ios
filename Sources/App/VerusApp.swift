import SwiftUI

@main
struct VerusApp: App {
    @State private var weight = WeightStore()
    @State private var activity = ActivityStore()
    @State private var progress = ProgressStore()

    var body: some Scene {
        WindowGroup {
            RootView(weight: weight, activity: activity, progress: progress)
        }
    }
}

/// Four of the concept's five screens. Food is the one still missing, and it
/// is the one waiting on the photo-to-calorie spike — adding it is a `Tab`
/// here and nothing else.
struct RootView: View {
    @Bindable var weight: WeightStore
    @Bindable var activity: ActivityStore
    @Bindable var progress: ProgressStore

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
            Tab("Progress", systemImage: "photo.on.rectangle.angled") {
                ProgressTimelineView(progress: progress, weight: weight)
            }
        }
    }
}
