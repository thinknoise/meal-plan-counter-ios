import SwiftUI

@main
struct MealPlanCounterApp: App {
    @StateObject private var store = MealPlanStore()
    @StateObject private var cafeReminder = CafeReminder()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, cafeReminder: cafeReminder)
                .preferredColorScheme(.dark)
        }
    }
}
