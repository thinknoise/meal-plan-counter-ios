import Foundation

enum MealPlanType: String, Codable, CaseIterable, Identifiable {
    case weekly5
    case weekly10
    case weekly14
    case weekly17
    case block140

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly5: "5 meals/week + Flex"
        case .weekly10: "10 meals/week + Flex"
        case .weekly14: "14 meals/week + Flex"
        case .weekly17: "17 meals/week + Flex"
        case .block140: "140 Block Plan"
        }
    }

    var totalMeals: Int {
        switch self {
        case .weekly5: 5
        case .weekly10: 10
        case .weekly14: 14
        case .weekly17: 17
        case .block140: 140
        }
    }

    var isWeekly: Bool { self != .block140 }

    init?(weeklyMeals: Int) {
        switch weeklyMeals {
        case 5: self = .weekly5
        case 10: self = .weekly10
        case 14: self = .weekly14
        case 17: self = .weekly17
        default: return nil
        }
    }
}

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"

    var id: String { rawValue }

    static func inferred(at date: Date, calendar: Calendar = .current) -> MealType {
        let hour = calendar.component(.hour, from: date)
        if hour < 11 { return .breakfast }
        if hour < 16 { return .lunch }
        return .dinner
    }
}

struct MealRecord: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case started
        case used
        case adjusted
        case imported
        case reset
    }

    let id: UUID
    let timestamp: Date
    var remainingMeals: Int
    let kind: Kind
    var mealType: MealType?

    init(kind: Kind, remainingMeals: Int, at timestamp: Date, mealType: MealType? = nil) {
        id = UUID()
        self.timestamp = timestamp
        self.remainingMeals = remainingMeals
        self.kind = kind
        self.mealType = mealType
    }
}

struct MealPlan: Codable, Equatable {
    var name: String
    var planType: MealPlanType?
    var legacyTotalMeals: Int
    var legacyUsedMeals: Int
    var blockUsedMeals: Int
    var weeklyUsedMeals: Int
    var weeklyResetAnchor: Date
    var canUndoLastMeal: Bool
    var records: [MealRecord]

    init(name: String, planType: MealPlanType, recordedAt: Date = .now) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.planType = planType
        legacyTotalMeals = planType.totalMeals
        legacyUsedMeals = 0
        blockUsedMeals = 0
        weeklyUsedMeals = 0
        weeklyResetAnchor = recordedAt
        canUndoLastMeal = false
        records = [MealRecord(kind: .started, remainingMeals: planType.totalMeals, at: recordedAt)]
    }

    var totalMeals: Int { planType?.totalMeals ?? legacyTotalMeals }

    var usedMeals: Int {
        guard let planType else { return legacyUsedMeals }
        return planType.isWeekly ? weeklyUsedMeals : blockUsedMeals
    }

    var remainingMeals: Int { totalMeals - usedMeals }
    var fractionUsed: Double { Double(usedMeals) / Double(totalMeals) }

    @discardableResult
    mutating func useMeal(at timestamp: Date = .now, calendar: Calendar = .current) -> Bool {
        resetWeeklyIfNeeded(at: timestamp, calendar: calendar)
        guard remainingMeals > 0 else { return false }
        if let planType {
            if planType.isWeekly {
                weeklyUsedMeals += 1
            } else {
                blockUsedMeals += 1
            }
        } else {
            legacyUsedMeals += 1
        }
        records.append(MealRecord(kind: .used, remainingMeals: remainingMeals, at: timestamp,
                                  mealType: MealType.inferred(at: timestamp, calendar: calendar)))
        canUndoLastMeal = true
        return true
    }

    mutating func updateMealType(for recordID: UUID, to mealType: MealType) -> Bool {
        guard let index = records.firstIndex(where: { $0.id == recordID && $0.kind == .used }) else { return false }
        records[index].mealType = mealType
        return true
    }

    // A backdated meal belongs to the current plan and only changes balances in its own
    // weekly allowance (or the rest of the semester for the block plan).
    @discardableResult
    mutating func addPastMeal(type: MealType, at timestamp: Date, now: Date = .now,
                              calendar: Calendar = .current) -> Bool {
        resetWeeklyIfNeeded(at: now, calendar: calendar)
        guard planType != nil, timestamp <= now, timestamp >= currentPlanStart else { return false }

        let affectedWeek = planType?.isWeekly == true ? weekStart(for: timestamp, calendar: calendar) : nil
        let currentWeek = planType?.isWeekly == true ? weekStart(for: now, calendar: calendar) : nil
        let relevantRecords = records.filter { record in
            record.timestamp >= currentPlanStart &&
            (affectedWeek == nil || weekStart(for: record.timestamp, calendar: calendar) == affectedWeek)
        }
        let lowestBalance = relevantRecords.map(\.remainingMeals).min() ?? totalMeals
        guard lowestBalance > 0, affectedWeek != currentWeek || remainingMeals > 0 else { return false }

        let balanceBeforeMeal = relevantRecords.last(where: { $0.timestamp <= timestamp })?.remainingMeals ?? totalMeals
        guard balanceBeforeMeal > 0 else { return false }

        for index in records.indices where records[index].kind == .used &&
            records[index].timestamp > timestamp && records[index].timestamp >= currentPlanStart &&
            (affectedWeek == nil || weekStart(for: records[index].timestamp, calendar: calendar) == affectedWeek) {
            records[index].remainingMeals -= 1
        }

        let record = MealRecord(kind: .used, remainingMeals: balanceBeforeMeal - 1,
                                at: timestamp, mealType: type)
        let insertionIndex = records.firstIndex(where: { $0.timestamp > timestamp }) ?? records.endIndex
        records.insert(record, at: insertionIndex)

        if planType?.isWeekly == true {
            if affectedWeek == currentWeek { weeklyUsedMeals += 1 }
        } else {
            blockUsedMeals += 1
        }
        canUndoLastMeal = false
        return true
    }

    var currentPlanStart: Date {
        records.last(where: { $0.kind == .started || $0.kind == .adjusted || $0.kind == .imported })?.timestamp
            ?? records.first?.timestamp ?? .distantPast
    }

    func nextWeeklyReset(after date: Date, calendar: Calendar = .current) -> Date? {
        guard planType?.isWeekly == true else { return nil }
        return calendar.date(byAdding: .day, value: 7, to: weekStart(for: date, calendar: calendar))
    }

    func daysUntilWeeklyReset(after date: Date, calendar: Calendar = .current) -> Int? {
        guard let reset = nextWeeklyReset(after: date, calendar: calendar) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: reset).day
    }

    private func weekStart(for date: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: date)
        let daysSinceSunday = calendar.component(.weekday, from: date) - 1
        return calendar.date(byAdding: .day, value: -daysSinceSunday, to: today)!
    }

    @discardableResult
    mutating func undoLastMeal() -> Bool {
        guard canUndoLastMeal, usedMeals > 0, records.last?.kind == .used else { return false }
        if let planType {
            if planType.isWeekly {
                weeklyUsedMeals -= 1
            } else {
                blockUsedMeals -= 1
            }
        } else {
            legacyUsedMeals -= 1
        }
        records.removeLast()
        canUndoLastMeal = false
        return true
    }

    @discardableResult
    mutating func resetWeeklyIfNeeded(at timestamp: Date = .now, calendar: Calendar = .current) -> Bool {
        guard planType?.isWeekly == true else { return false }
        let sunday = weekStart(for: timestamp, calendar: calendar)
        guard sunday > weeklyResetAnchor else { return false }

        weeklyUsedMeals = 0
        weeklyResetAnchor = sunday
        canUndoLastMeal = false
        records.append(MealRecord(kind: .reset, remainingMeals: remainingMeals, at: sunday))
        return true
    }

    mutating func updateSettings(name: String, planType newType: MealPlanType, at timestamp: Date = .now) {
        let oldType = planType
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard oldType != newType else { return }
        planType = newType
        if newType.isWeekly {
            weeklyUsedMeals = 0
            weeklyResetAnchor = timestamp
        } else {
            blockUsedMeals = 0
        }
        canUndoLastMeal = false

        if oldType == nil {
            // The first official plan replaces an old custom count and its sample history.
            records = [MealRecord(kind: .started, remainingMeals: remainingMeals, at: timestamp)]
        } else {
            records.append(MealRecord(kind: .adjusted, remainingMeals: remainingMeals, at: timestamp))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case name, totalMeals, usedMeals, canUndoLastMeal, records
        case planType, legacyTotalMeals, legacyUsedMeals, blockUsedMeals
        case weeklyUsedMeals, weeklyResetAnchor
        case mode, semesterTotalMeals, semesterUsedMeals, weeklyMealsPerWeek
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let oldTotal = max(1, try values.decodeIfPresent(Int.self, forKey: .totalMeals) ?? 1)
        let oldUsed = min(max(0, try values.decodeIfPresent(Int.self, forKey: .usedMeals) ?? 0), oldTotal)
        let oldMode = try values.decodeIfPresent(String.self, forKey: .mode)
        let previousWeeklyMeals = try values.decodeIfPresent(Int.self, forKey: .weeklyMealsPerWeek)
        let migratedType = oldMode == "weekly" ? previousWeeklyMeals.flatMap(MealPlanType.init(weeklyMeals:)) : nil
        let unmatchedWeeklyPlan = oldMode == "weekly" && migratedType == nil

        name = try values.decode(String.self, forKey: .name)
        planType = try values.decodeIfPresent(MealPlanType.self, forKey: .planType) ?? migratedType
        legacyTotalMeals = max(1, try values.decodeIfPresent(Int.self, forKey: .legacyTotalMeals)
            ?? (unmatchedWeeklyPlan ? oldTotal : values.decodeIfPresent(Int.self, forKey: .semesterTotalMeals) ?? oldTotal))
        legacyUsedMeals = min(max(0, try values.decodeIfPresent(Int.self, forKey: .legacyUsedMeals)
            ?? (unmatchedWeeklyPlan ? oldUsed : values.decodeIfPresent(Int.self, forKey: .semesterUsedMeals) ?? oldUsed)), legacyTotalMeals)
        blockUsedMeals = min(max(0, try values.decodeIfPresent(Int.self, forKey: .blockUsedMeals) ?? 0), 140)
        let weeklyLimit = planType?.isWeekly == true ? (planType?.totalMeals ?? 17) : 17
        weeklyUsedMeals = min(max(0, try values.decodeIfPresent(Int.self, forKey: .weeklyUsedMeals)
            ?? (planType?.isWeekly == true ? oldUsed : 0)), weeklyLimit)
        weeklyResetAnchor = try values.decodeIfPresent(Date.self, forKey: .weeklyResetAnchor) ?? .now
        canUndoLastMeal = false
        records = []

        if let savedRecords = try values.decodeIfPresent([MealRecord].self, forKey: .records),
           !savedRecords.isEmpty {
            records = savedRecords
            let savedUndo = try values.decodeIfPresent(Bool.self, forKey: .canUndoLastMeal) ?? false
            canUndoLastMeal = savedUndo && usedMeals > 0 && records.last?.kind == .used
        } else {
            // Older versions saved the balance but no dates of meal use.
            records = [MealRecord(kind: .imported, remainingMeals: remainingMeals, at: .now)]
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(name, forKey: .name)
        try values.encode(totalMeals, forKey: .totalMeals)
        try values.encode(usedMeals, forKey: .usedMeals)
        try values.encode(canUndoLastMeal, forKey: .canUndoLastMeal)
        try values.encode(records, forKey: .records)
        try values.encodeIfPresent(planType, forKey: .planType)
        try values.encode(legacyTotalMeals, forKey: .legacyTotalMeals)
        try values.encode(legacyUsedMeals, forKey: .legacyUsedMeals)
        try values.encode(blockUsedMeals, forKey: .blockUsedMeals)
        try values.encode(weeklyUsedMeals, forKey: .weeklyUsedMeals)
        try values.encode(weeklyResetAnchor, forKey: .weeklyResetAnchor)
    }
}
