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

enum MealPlanTerm: String, Codable, CaseIterable, Identifiable {
    case fall2026
    case spring2027

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fall2026: "Fall 2026"
        case .spring2027: "Spring 2027"
        }
    }

    // CalArts 2026–27 Meal Plans: https://calarts.edu/admissions-aid/tuition/tuition-and-fees/meal-plans
    var startDate: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        switch self {
        case .fall2026:
            return calendar.date(from: DateComponents(year: 2026, month: 8, day: 29))!
        case .spring2027:
            return calendar.date(from: DateComponents(year: 2027, month: 1, day: 10))!
        }
    }

    static func containing(_ date: Date) -> MealPlanTerm {
        date >= MealPlanTerm.spring2027.startDate ? .spring2027 : .fall2026
    }
}

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"

    var id: String { rawValue }

    static func inferred(at date: Date, calendar: Calendar = .current) -> MealType {
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let weekday = calendar.component(.weekday, from: date)
        let services = CafeHours.mealServices(for: weekday)
        if let meal = services.first(where: {
            minute >= $0.service.startMinute && minute < $0.service.endMinute
        }) {
            return meal.mealType
        }
        // Outside regular service, use the surrounding meal boundaries as a default.
        if let breakfast = services.first(where: { $0.mealType == .breakfast }),
           minute < breakfast.service.endMinute { return .breakfast }
        if let dinner = services.first(where: { $0.mealType == .dinner }),
           minute < dinner.service.startMinute { return .lunch }
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

    enum EntryAction: String, Codable {
        case tapped
        case edited
        case added
    }

    let id: UUID
    var timestamp: Date
    var remainingMeals: Int
    let kind: Kind
    var mealType: MealType?
    var tappedAt: Date?
    var recordedAt: Date?
    var lastAction: EntryAction?
    // Preserve the original allowance when backdated meals change the saved start balance.
    var startingAllowance: Int?
    var planTerm: MealPlanTerm?

    init(kind: Kind, remainingMeals: Int, at timestamp: Date, mealType: MealType? = nil,
         tappedAt: Date? = nil, recordedAt: Date? = nil, lastAction: EntryAction? = nil,
         startingAllowance: Int? = nil, planTerm: MealPlanTerm? = nil) {
        id = UUID()
        self.timestamp = timestamp
        self.remainingMeals = remainingMeals
        self.kind = kind
        self.mealType = mealType
        self.tappedAt = tappedAt
        self.recordedAt = recordedAt
        self.lastAction = lastAction
        self.startingAllowance = startingAllowance
        self.planTerm = planTerm
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
    var semesterStartDate: Date? // Retained to decode dates chosen in older app versions.
    var planTerm: MealPlanTerm
    var canUndoLastMeal: Bool
    var records: [MealRecord]

    init(name: String, planType: MealPlanType, term: MealPlanTerm? = nil,
         recordedAt: Date = .now) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.planType = planType
        planTerm = term ?? MealPlanTerm.containing(recordedAt)
        legacyTotalMeals = planType.totalMeals
        legacyUsedMeals = 0
        blockUsedMeals = 0
        weeklyUsedMeals = 0
        weeklyResetAnchor = max(recordedAt, planTerm.startDate)
        semesterStartDate = nil
        canUndoLastMeal = false
        records = [MealRecord(kind: .started, remainingMeals: planType.totalMeals,
                              at: recordedAt, planTerm: planTerm)]
    }

    var planStartDate: Date { planTerm.startDate }
    var totalMeals: Int { planType?.totalMeals ?? legacyTotalMeals }

    var usedMeals: Int {
        guard let planType else { return legacyUsedMeals }
        return planType.isWeekly ? weeklyUsedMeals : blockUsedMeals
    }

    var remainingMeals: Int { totalMeals - usedMeals }
    var fractionUsed: Double { Double(usedMeals) / Double(totalMeals) }

    @discardableResult
    mutating func useMeal(at timestamp: Date = .now, calendar: Calendar = .current) -> Bool {
        guard timestamp >= planStartDate else { return false }
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
                                  tappedAt: timestamp, lastAction: .tapped))
        canUndoLastMeal = true
        return true
    }

    mutating func updateMealType(for recordID: UUID, to mealType: MealType,
                                 at editedAt: Date = .now) -> Bool {
        guard let index = records.firstIndex(where: { $0.id == recordID && $0.kind == .used }) else { return false }
        guard records[index].mealType != mealType else { return false }
        records[index].mealType = mealType
        records[index].recordedAt = editedAt
        records[index].lastAction = .edited
        return true
    }

    func editableDateRange(for recordID: UUID, now: Date = .now) -> ClosedRange<Date>? {
        guard let index = records.firstIndex(where: { $0.id == recordID && $0.kind == .used }),
              let start = epochStartIndex(containing: index) else { return nil }
        let end = epochEndIndex(after: start)
        let latest = end == records.endIndex
            ? now : min(now, displayDate(for: records[end]).addingTimeInterval(-1))
        let earliest = start == records.firstIndex(where: { Self.startsPlan($0.kind) }) ||
            isTermStart(records[start])
            ? epochTerm(start: start).startDate
            : max(records[start].timestamp, epochTerm(start: start).startDate)
        guard latest >= earliest else { return nil }
        return earliest...latest
    }

    func isWeeklyPeriod(for recordID: UUID) -> Bool {
        guard let index = records.firstIndex(where: { $0.id == recordID && $0.kind == .used }),
              let start = epochStartIndex(containing: index) else { return false }
        return isWeeklyEpoch(start: start, end: epochEndIndex(after: start))
    }

    func isTermStart(_ record: MealRecord) -> Bool {
        guard record.kind == .adjusted, let newTerm = record.planTerm,
              let index = records.firstIndex(where: { $0.id == record.id }),
              let previous = records[..<index].lastIndex(where: { Self.startsPlan($0.kind) }) else {
            return false
        }
        return newTerm != epochTerm(start: previous)
    }

    func displayDate(for record: MealRecord) -> Date {
        if record.kind == .started,
           let start = records.firstIndex(where: { $0.id == record.id }) {
            return epochTerm(start: start).startDate
        }
        if isTermStart(record), let term = record.planTerm { return term.startDate }
        return record.timestamp
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
        replacement.lastAction = .edited
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
        if records[index].timestamp < records[start].timestamp &&
            (affectedWeek.map { weekStart(for: records[start].timestamp, calendar: calendar) == $0 } ?? true) {
            records[start].remainingMeals += 1
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
        guard planType != nil, timestamp >= planStartDate, timestamp <= now else { return false }
        let record = MealRecord(kind: .used, remainingMeals: 0,
                                at: timestamp, mealType: type, recordedAt: now, lastAction: .added)
        return insertPastMeal(record, now: now, calendar: calendar)
    }

    private mutating func insertPastMeal(_ newRecord: MealRecord, now: Date,
                                         calendar: Calendar) -> Bool {
        let timestamp = newRecord.timestamp
        guard timestamp <= now else { return false }
        let start = records.lastIndex(where: {
            Self.startsPlan($0.kind) &&
                ($0.timestamp <= timestamp || (isTermStart($0) && displayDate(for: $0) <= timestamp))
        }) ?? records.firstIndex(where: { Self.startsPlan($0.kind) })
        guard let start else { return false }
        guard timestamp >= epochTerm(start: start).startDate else { return false }
        let beforeTracking = timestamp < records[start].timestamp
        let end = epochEndIndex(after: start)
        guard end == records.endIndex || timestamp < displayDate(for: records[end]) else { return false }

        let isWeekly = isWeeklyEpoch(start: start, end: end)
        let affectedWeek = isWeekly ? weekStart(for: timestamp, calendar: calendar) : nil
        let allowance = start == currentEpochStartIndex && records[start].kind != .imported
            ? totalMeals : records[start].startingAllowance ?? records[start].remainingMeals
        let firstRelevantIndex = beforeTracking && !isTermStart(records[start])
            ? records.startIndex : start + 1
        let relevant = (firstRelevantIndex..<end).filter { index in
            records[index].kind == .used &&
            (affectedWeek.map { weekStart(for: records[index].timestamp, calendar: calendar) == $0 } ?? true)
        }
        let insertionIndex = (firstRelevantIndex..<end).first {
            records[$0].timestamp > timestamp ||
                (records[$0].timestamp == timestamp && records[$0].kind == .used)
        } ?? end
        let lowestBalance = min(allowance, relevant.map { records[$0].remainingMeals }.min() ?? allowance)
        guard lowestBalance > 0 else { return false }
        let balanceBeforeMeal = relevant.last(where: { $0 < insertionIndex })
            .map { records[$0].remainingMeals } ?? allowance
        guard balanceBeforeMeal > 0 else { return false }

        let isCurrentEpoch = start == currentEpochStartIndex
        let currentWeek = isWeekly ? weekStart(for: now, calendar: calendar) : nil
        guard !isCurrentEpoch || affectedWeek != currentWeek || remainingMeals > 0 else { return false }

        for index in relevant where index >= insertionIndex {
            records[index].remainingMeals -= 1
        }
        if beforeTracking {
            if records[start].startingAllowance == nil {
                records[start].startingAllowance = records[start].remainingMeals
            }
            if affectedWeek.map({ weekStart(for: records[start].timestamp, calendar: calendar) == $0 }) ?? true {
                records[start].remainingMeals -= 1
            }
        }
        var record = newRecord
        record.remainingMeals = balanceBeforeMeal - 1
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
        // A backfilled meal before tracking belongs to the first plan period.
        records[...index].lastIndex(where: { Self.startsPlan($0.kind) })
            ?? records.firstIndex(where: { Self.startsPlan($0.kind) })
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
            MealPlanType(weeklyMeals: records[start].startingAllowance ?? records[start].remainingMeals) != nil
    }

    private func epochTerm(start: Int) -> MealPlanTerm {
        records[start].planTerm ??
            (start == currentEpochStartIndex ? planTerm : MealPlanTerm.containing(records[start].timestamp))
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
        guard planType?.isWeekly == true, timestamp >= planStartDate else { return false }
        let sunday = weekStart(for: timestamp, calendar: calendar)
        guard sunday > weeklyResetAnchor else { return false }

        weeklyUsedMeals = 0
        weeklyResetAnchor = sunday
        canUndoLastMeal = false
        records.append(MealRecord(kind: .reset, remainingMeals: remainingMeals, at: sunday))
        return true
    }

    mutating func updateSettings(name: String, planType newType: MealPlanType,
                                 term newTerm: MealPlanTerm, at timestamp: Date = .now) {
        let oldType = planType
        let oldTerm = planTerm
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        planTerm = newTerm

        guard oldType != newType || oldTerm != newTerm else { return }
        planType = newType
        if newType.isWeekly {
            weeklyUsedMeals = 0
            weeklyResetAnchor = max(timestamp, newTerm.startDate)
        } else {
            blockUsedMeals = 0
        }
        canUndoLastMeal = false

        if oldType == nil {
            // The first official plan replaces an old custom count and its sample history.
            records = [MealRecord(kind: .started, remainingMeals: remainingMeals,
                                  at: timestamp, planTerm: newTerm)]
        } else {
            records.append(MealRecord(kind: .adjusted, remainingMeals: remainingMeals,
                                      at: timestamp, planTerm: newTerm))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case name, totalMeals, usedMeals, canUndoLastMeal, records
        case planType, legacyTotalMeals, legacyUsedMeals, blockUsedMeals
        case weeklyUsedMeals, weeklyResetAnchor, semesterStartDate, planTerm
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
        let savedTerm = try values.decodeIfPresent(MealPlanTerm.self, forKey: .planTerm)
        planTerm = savedTerm ?? MealPlanTerm.containing(semesterStartDate ?? weeklyResetAnchor)
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
        if savedTerm == nil {
            let termDate = semesterStartDate ?? records.last(where: { Self.startsPlan($0.kind) })?.timestamp
                ?? weeklyResetAnchor
            planTerm = MealPlanTerm.containing(termDate)
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
        try values.encode(planTerm, forKey: .planTerm)
    }
}
