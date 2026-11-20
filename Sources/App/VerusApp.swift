import SwiftUI

@main
struct VerusApp: App {
    @State private var store = WeightStore()

    var body: some Scene {
        WindowGroup {
            WeightView(store: store)
        }
    }
}
