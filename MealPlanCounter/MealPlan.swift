import Foundation

struct MealRecord: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case started
        case used
        case adjusted
        case imported
    }

    let id: UUID
    let timestamp: Date
    let remainingMeals: Int
    let kind: Kind

    init(kind: Kind, remainingMeals: Int, at timestamp: Date) {
        id = UUID()
        self.timestamp = timestamp
        self.remainingMeals = remainingMeals
        self.kind = kind
    }
}

struct MealPlan: Codable, Equatable {
    var name: String
    var totalMeals: Int
    var usedMeals: Int
    var canUndoLastMeal: Bool
    var records: [MealRecord]

    init(name: String, totalMeals: Int, usedMeals: Int = 0, recordedAt: Date = .now) {
        let total = max(1, totalMeals)
        let used = min(max(0, usedMeals), total)
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.totalMeals = total
        self.usedMeals = used
        canUndoLastMeal = false
        records = [MealRecord(kind: .started, remainingMeals: total - used, at: recordedAt)]
    }

    var remainingMeals: Int { totalMeals - usedMeals }
    var fractionUsed: Double { Double(usedMeals) / Double(totalMeals) }

    @discardableResult
    mutating func useMeal(at timestamp: Date = .now) -> Bool {
        guard remainingMeals > 0 else { return false }
        usedMeals += 1
        records.append(MealRecord(kind: .used, remainingMeals: remainingMeals, at: timestamp))
        canUndoLastMeal = true
        return true
    }

    @discardableResult
    mutating func undoLastMeal() -> Bool {
        guard canUndoLastMeal, usedMeals > 0, records.last?.kind == .used else { return false }
        usedMeals -= 1
        records.removeLast()
        canUndoLastMeal = false
        return true
    }

    mutating func update(name: String, totalMeals: Int, usedMeals: Int, at timestamp: Date = .now) {
        let previousTotal = self.totalMeals
        let previousUsed = self.usedMeals
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.totalMeals = max(1, totalMeals)
        self.usedMeals = min(max(0, usedMeals), self.totalMeals)
        if self.totalMeals != previousTotal || self.usedMeals != previousUsed {
            records.append(MealRecord(kind: .adjusted, remainingMeals: remainingMeals, at: timestamp))
        }
        canUndoLastMeal = false
    }

    private enum CodingKeys: String, CodingKey {
        case name, totalMeals, usedMeals, canUndoLastMeal, records
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let total = max(1, try values.decode(Int.self, forKey: .totalMeals))
        let used = min(max(0, try values.decode(Int.self, forKey: .usedMeals)), total)
        name = try values.decode(String.self, forKey: .name)
        totalMeals = total
        usedMeals = used
        canUndoLastMeal = false

        if let savedRecords = try values.decodeIfPresent([MealRecord].self, forKey: .records),
           !savedRecords.isEmpty {
            records = savedRecords
            let savedUndo = try values.decodeIfPresent(Bool.self, forKey: .canUndoLastMeal) ?? false
            canUndoLastMeal = savedUndo && usedMeals > 0 && records.last?.kind == .used
        } else {
            // Older app versions saved the balance but no dates of meal use.
            records = [MealRecord(kind: .imported, remainingMeals: total - used, at: .now)]
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(name, forKey: .name)
        try values.encode(totalMeals, forKey: .totalMeals)
        try values.encode(usedMeals, forKey: .usedMeals)
        try values.encode(canUndoLastMeal, forKey: .canUndoLastMeal)
        try values.encode(records, forKey: .records)
    }
}
