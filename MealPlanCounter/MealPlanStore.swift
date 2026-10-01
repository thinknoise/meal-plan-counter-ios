import Foundation
import Combine

@MainActor
final class MealPlanStore: ObservableObject {
    @Published private(set) var plan: MealPlan?

    private let storageKey = "lilys-meal-plan-v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           var savedPlan = try? JSONDecoder().decode(MealPlan.self, from: data) {
            savedPlan.resetWeeklyIfNeeded()
            plan = savedPlan
            // Persist records created by migration or an overdue weekly reset.
            save()
        }
    }

    func create(name: String, planType: MealPlanType) {
        plan = MealPlan(name: name, planType: planType)
        save()
    }

    func useMeal() {
        guard var current = plan, current.useMeal() else { return }
        plan = current
        save()
    }

    @discardableResult
    func addPastMeal(type: MealType, at timestamp: Date) -> Bool {
        refreshWeeklyReset()
        guard var current = plan, current.addPastMeal(type: type, at: timestamp) else { return false }
        plan = current
        save()
        return true
    }

    @discardableResult
    func editMeal(recordID: UUID, type: MealType, at timestamp: Date) -> Bool {
        refreshWeeklyReset()
        guard var current = plan, current.editMeal(recordID: recordID, type: type, at: timestamp) else { return false }
        plan = current
        save()
        return true
    }

    @discardableResult
    func removeMeal(recordID: UUID) -> Bool {
        refreshWeeklyReset()
        guard var current = plan, current.removeMeal(recordID: recordID) else { return false }
        plan = current
        save()
        return true
    }

    func undoLastMeal() {
        refreshWeeklyReset()
        guard var current = plan, current.undoLastMeal() else { return }
        plan = current
        save()
    }

    func updateSettings(name: String, planType: MealPlanType, semesterStartDate: Date?) {
        guard var current = plan else { return }
        let now = Date()
        current.resetWeeklyIfNeeded(at: now)
        current.updateSettings(name: name, planType: planType,
                               semesterStartDate: semesterStartDate, at: now)
        plan = current
        save()
    }

    func refreshWeeklyReset(at timestamp: Date = .now) {
        guard var current = plan, current.resetWeeklyIfNeeded(at: timestamp) else { return }
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
