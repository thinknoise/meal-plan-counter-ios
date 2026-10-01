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
    var timestamp: Date
    var remainingMeals: Int
    let kind: Kind
    var mealType: MealType?
    var tappedAt: Date?
    var recordedAt: Date?

    init(kind: Kind, remainingMeals: Int, at timestamp: Date, mealType: MealType? = nil,
         tappedAt: Date? = nil, recordedAt: Date? = nil) {
        id = UUID()
        self.timestamp = timestamp
        self.remainingMeals = remainingMeals
        self.kind = kind
        self.mealType = mealType
        self.tappedAt = tappedAt
        self.recordedAt = recordedAt
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
    var semesterStartDate: Date?
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
        semesterStartDate = nil
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
                                  mealType: MealType.inferred(at: timestamp, calendar: calendar),
                                  tappedAt: timestamp))
        canUndoLastMeal = true
        return true
    }

    mutating func updateMealType(for recordID: UUID, to mealType: MealType,
                                 at editedAt: Date = .now) -> Bool {
        guard let index = records.firstIndex(where: { $0.id == recordID && $0.kind == .used }) else { return false }
        guard records[index].mealType != mealType else { return false }
        records[index].mealType = mealType
        records[index].recordedAt = editedAt
        return true
    }

    func editableDateRange(for recordID: UUID, now: Date = .now) -> ClosedRange<Date>? {
        guard let index = records.firstIndex(where: { $0.id == recordID && $0.kind == .used }),
              let start = epochStartIndex(containing: index) else { return nil }
        let end = epochEndIndex(after: start)
        let latest = end == records.endIndex
            ? now : min(now, records[end].timestamp.addingTimeInterval(-1))
        guard latest >= records[start].timestamp else { return nil }
        return records[start].timestamp...latest
    }

    @discardableResult
    mutating func editMeal(recordID: UUID, type: MealType, at timestamp: Date,
                           now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let index = records.firstIndex(where: { $0.id == recordID && $0.kind == .used }) else { return false }
        if records[index].timestamp == timestamp {
            return records[index].mealType == type || updateMealType(for: recordID, to: type, at: now)
        }
        guard let allowedDates = editableDateRange(for: recordID, now: now),
              allowedDates.contains(timestamp) else { return false }

        var updated = self
        var replacement = records[index]
        guard updated.removeMeal(recordID: recordID, now: now, calendar: calendar) else { return false }
        replacement.timestamp = timestamp
        replacement.mealType = type
        replacement.recordedAt = now
        guard updated.insertPastMeal(replacement, now: now, calendar: calendar) else { return false }
        self = updated
        return true
    }

    @discardableResult
    mutating func removeMeal(recordID: UUID, now: Date = .now,
                             calendar: Calendar = .current) -> Bool {
        resetWeeklyIfNeeded(at: now, calendar: calendar)
        guard let index = records.firstIndex(where: { $0.id == recordID && $0.kind == .used }),
              let start = epochStartIndex(containing: index) else { return false }
        let end = epochEndIndex(after: start)
        let affectedWeek = isWeeklyEpoch(start: start, end: end)
            ? weekStart(for: records[index].timestamp, calendar: calendar) : nil

        for later in (index + 1)..<end where records[later].kind == .used &&
            (affectedWeek.map { weekStart(for: records[later].timestamp, calendar: calendar) == $0 } ?? true) {
            records[later].remainingMeals += 1
        }

        if start == currentEpochStartIndex {
            if let planType {
                if planType.isWeekly {
                    if affectedWeek == weekStart(for: now, calendar: calendar) {
                        weeklyUsedMeals = max(0, weeklyUsedMeals - 1)
                    }
                } else {
                    blockUsedMeals = max(0, blockUsedMeals - 1)
                }
            } else {
                legacyUsedMeals = max(0, legacyUsedMeals - 1)
            }
        }
        records.remove(at: index)
        canUndoLastMeal = false
        return true
    }

    // A backdated meal belongs to the current plan and only changes balances in its own
    // weekly allowance (or the rest of the semester for the block plan).
    @discardableResult
    mutating func addPastMeal(type: MealType, at timestamp: Date, now: Date = .now,
                              calendar: Calendar = .current) -> Bool {
        resetWeeklyIfNeeded(at: now, calendar: calendar)
        guard planType != nil, timestamp <= now, timestamp >= currentPlanStart else { return false }
        let record = MealRecord(kind: .used, remainingMeals: 0,
                                at: timestamp, mealType: type, recordedAt: now)
        return insertPastMeal(record, now: now, calendar: calendar)
    }

    private mutating func insertPastMeal(_ newRecord: MealRecord, now: Date,
                                         calendar: Calendar) -> Bool {
        let timestamp = newRecord.timestamp
        guard timestamp <= now,
              let start = records.lastIndex(where: {
                  Self.startsPlan($0.kind) && $0.timestamp <= timestamp
              }) else { return false }
        let end = epochEndIndex(after: start)
        guard end == records.endIndex || timestamp < records[end].timestamp else { return false }

        let isWeekly = isWeeklyEpoch(start: start, end: end)
        let affectedWeek = isWeekly ? weekStart(for: timestamp, calendar: calendar) : nil
        let allowance = start == currentEpochStartIndex && records[start].kind != .imported
            ? totalMeals : records[start].remainingMeals
        let relevant = (start..<end).filter { index in
            records[index].kind == .used &&
            (affectedWeek.map { weekStart(for: records[index].timestamp, calendar: calendar) == $0 } ?? true)
        }
        let lowestBalance = min(allowance, relevant.map { records[$0].remainingMeals }.min() ?? allowance)
        guard lowestBalance > 0 else { return false }
        let balanceBeforeMeal = relevant.last(where: { records[$0].timestamp <= timestamp })
            .map { records[$0].remainingMeals } ?? allowance
        guard balanceBeforeMeal > 0 else { return false }

        let isCurrentEpoch = start == currentEpochStartIndex
        let currentWeek = isWeekly ? weekStart(for: now, calendar: calendar) : nil
        guard !isCurrentEpoch || affectedWeek != currentWeek || remainingMeals > 0 else { return false }

        for index in relevant where records[index].timestamp > timestamp {
            records[index].remainingMeals -= 1
        }
        var record = newRecord
        record.remainingMeals = balanceBeforeMeal - 1
        let insertionIndex = records.firstIndex(where: { $0.timestamp > timestamp }) ?? records.endIndex
        records.insert(record, at: insertionIndex)

        if isCurrentEpoch {
            if let planType {
                if planType.isWeekly {
                    if affectedWeek == currentWeek { weeklyUsedMeals += 1 }
                } else {
                    blockUsedMeals += 1
                }
            } else {
                legacyUsedMeals += 1
            }
        }
        canUndoLastMeal = false
        return true
    }

    private static func startsPlan(_ kind: MealRecord.Kind) -> Bool {
        kind == .started || kind == .adjusted || kind == .imported
    }

    private var currentEpochStartIndex: Int? {
        records.lastIndex(where: { Self.startsPlan($0.kind) })
    }

    private func epochStartIndex(containing index: Int) -> Int? {
        records[...index].lastIndex(where: { Self.startsPlan($0.kind) })
    }

    private func epochEndIndex(after start: Int) -> Int {
        for index in (start + 1)..<records.endIndex where Self.startsPlan(records[index].kind) {
            return index
        }
        return records.endIndex
    }

    private func isWeeklyEpoch(start: Int, end: Int) -> Bool {
        if start == currentEpochStartIndex { return planType?.isWeekly == true }
        if records[start..<end].contains(where: { $0.kind == .reset }) { return true }
        // Older plan periods did not save their type; their starting allowance identifies official weekly plans.
        return records[start].kind != .imported &&
            MealPlanType(weeklyMeals: records[start].remainingMeals) != nil
    }

    var currentPlanStart: Date {
        records.last(where: { $0.kind == .started || $0.kind == .adjusted || $0.kind == .imported })?.timestamp
            ?? records.first?.timestamp ?? .distantPast
    }

    func nextWeeklyReset(after date: Date, calendar: Calendar = .current) -> Date? {
        guard planType?.isWeekly == true else { return nil }
        return calendar.date(byAdding: .day, value: 7, to: weekStart(for: date, calendar: calendar))
    }

    func currentWeeklyStart(at date: Date, calendar: Calendar = .current) -> Date? {
        guard planType?.isWeekly == true else { return nil }
        return weekStart(for: date, calendar: calendar)
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

    mutating func updateSettings(name: String, planType newType: MealPlanType,
                                 semesterStartDate newSemesterStart: Date? = nil, at timestamp: Date = .now) {
        let oldType = planType
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        semesterStartDate = newType == .block140 ? newSemesterStart : nil

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
        case weeklyUsedMeals, weeklyResetAnchor, semesterStartDate
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
        semesterStartDate = try values.decodeIfPresent(Date.self, forKey: .semesterStartDate)
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
        try values.encodeIfPresent(semesterStartDate, forKey: .semesterStartDate)
    }
}
