import Foundation

struct MealPlan: Codable, Equatable {
    var name: String
    var totalMeals: Int
    var usedMeals: Int
    var canUndoLastMeal: Bool

    init(name: String, totalMeals: Int, usedMeals: Int = 0, canUndoLastMeal: Bool = false) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.totalMeals = max(1, totalMeals)
        self.usedMeals = min(max(0, usedMeals), self.totalMeals)
        self.canUndoLastMeal = canUndoLastMeal && self.usedMeals > 0
    }

    var remainingMeals: Int { totalMeals - usedMeals }
    var fractionUsed: Double { Double(usedMeals) / Double(totalMeals) }

    @discardableResult
    mutating func useMeal() -> Bool {
        guard remainingMeals > 0 else { return false }
        usedMeals += 1
        canUndoLastMeal = true
        return true
    }

    @discardableResult
    mutating func undoLastMeal() -> Bool {
        guard canUndoLastMeal, usedMeals > 0 else { return false }
        usedMeals -= 1
        canUndoLastMeal = false
        return true
    }

    mutating func update(name: String, totalMeals: Int, usedMeals: Int) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.totalMeals = max(1, totalMeals)
        self.usedMeals = min(max(0, usedMeals), self.totalMeals)
        canUndoLastMeal = false
    }
}
