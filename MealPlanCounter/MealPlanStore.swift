import Foundation
import Combine

@MainActor
final class MealPlanStore: ObservableObject {
    @Published private(set) var plan: MealPlan?

    private let storageKey = "lilys-meal-plan-v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey) {
            plan = try? JSONDecoder().decode(MealPlan.self, from: data)
        }
    }

    func create(name: String, totalMeals: Int) {
        plan = MealPlan(name: name, totalMeals: totalMeals)
        save()
    }

    func useMeal() {
        guard var current = plan, current.useMeal() else { return }
        plan = current
        save()
    }

    func undoLastMeal() {
        guard var current = plan, current.undoLastMeal() else { return }
        plan = current
        save()
    }

    func update(name: String, totalMeals: Int, usedMeals: Int) {
        guard var current = plan else { return }
        current.update(name: name, totalMeals: totalMeals, usedMeals: usedMeals)
        plan = current
        save()
    }

    func clear() {
        plan = nil
        defaults.removeObject(forKey: storageKey)
    }

    private func save() {
        guard let plan, let data = try? JSONEncoder().encode(plan) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
