import SwiftUI

@main
struct MealPlanCounterApp: App {
    @StateObject private var store = MealPlanStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .preferredColorScheme(.dark)
        }
    }
}
