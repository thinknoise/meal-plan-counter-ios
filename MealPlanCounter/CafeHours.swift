import Foundation

struct CafeService: Equatable {
    let name: String
    let startMinute: Int
    let endMinute: Int
    let timeRange: String
    let openingTime: String
}

struct CafeStatus: Equatable {
    let isOpen: Bool
    let headline: String
    let detail: String
}

enum CafeHours {
    // Regular weekly schedules published by Bon Appétit for CalArts dining.
    // Special hours and academic breaks can differ from this offline schedule.
    static let sourceURL = URL(string: "https://calarts.cafebonappetit.com/")!
    static let tatumSourceURL = URL(string: "https://calarts.cafebonappetit.com/cafe/tatum/")!
    static let timeZone = TimeZone(identifier: "America/Los_Angeles")!

    static let weekdays = [
        CafeService(name: "Breakfast", startMinute: 7 * 60 + 30, endMinute: 11 * 60 + 30, timeRange: "7:30–11:30 AM", openingTime: "7:30 AM"),
        CafeService(name: "Lunch", startMinute: 11 * 60 + 30, endMinute: 13 * 60 + 30, timeRange: "11:30 AM–1:30 PM", openingTime: "11:30 AM"),
        CafeService(name: "Grill only", startMinute: 13 * 60 + 30, endMinute: 17 * 60, timeRange: "1:30–5 PM", openingTime: "1:30 PM"),
        CafeService(name: "Dinner", startMinute: 17 * 60, endMinute: 19 * 60 + 30, timeRange: "5–7:30 PM", openingTime: "5 PM"),
        CafeService(name: "Late night", startMinute: 19 * 60 + 30, endMinute: 22 * 60, timeRange: "7:30–10 PM", openingTime: "7:30 PM")
    ]

    static let weekends = [
        CafeService(name: "Breakfast", startMinute: 10 * 60, endMinute: 11 * 60 + 30, timeRange: "10–11:30 AM", openingTime: "10 AM"),
        CafeService(name: "Brunch", startMinute: 11 * 60 + 30, endMinute: 16 * 60, timeRange: "11:30 AM–4 PM", openingTime: "11:30 AM"),
        CafeService(name: "Late night", startMinute: 16 * 60, endMinute: 19 * 60, timeRange: "4–7 PM", openingTime: "4 PM")
    ]

    static let tatumWeekdays = [
        CafeService(name: "Coffee bar", startMinute: 8 * 60 + 30, endMinute: 21 * 60 + 30,
                    timeRange: "8:30 AM–9:30 PM", openingTime: "8:30 AM")
    ]

    static let tatumWeekends = [
        CafeService(name: "Coffee bar", startMinute: 9 * 60 + 30, endMinute: 17 * 60,
                    timeRange: "9:30 AM–5 PM", openingTime: "9:30 AM")
    ]

    private static var cafeCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static var deviceCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    static func mealPeriod(at date: Date) -> MealType? {
        let calendar = cafeCalendar
        let weekday = calendar.component(.weekday, from: date)
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        guard services(for: weekday).contains(where: {
            minute >= $0.startMinute && minute < $0.endMinute
        }) else { return nil }
        // The existing inference assigns weekday grill service to lunch and late night to dinner.
        return inferredMealPeriod(at: date)
    }

    static func inferredMealPeriod(at date: Date) -> MealType {
        MealType.inferred(at: date, calendar: cafeCalendar)
    }

    static func isSameMealDay(_ first: Date, _ second: Date) -> Bool {
        cafeCalendar.isDate(first, inSameDayAs: second)
    }

    static func suggestedUsageTime(for mealType: MealType, on selectedDate: Date) -> Date? {
        let selectedDay = deviceCalendar.dateComponents([.year, .month, .day], from: selectedDate)
        guard let cafeDay = cafeCalendar.date(from: selectedDay),
              let service = mealService(for: mealType, weekday: cafeCalendar.component(.weekday, from: cafeDay))
        else { return nil }

        var components = cafeCalendar.dateComponents([.year, .month, .day], from: cafeDay)
        let suggestedMinute = service.startMinute + 30
        components.hour = suggestedMinute / 60
        components.minute = suggestedMinute % 60
        return cafeCalendar.date(from: components)
    }

    static func usageTimestamp(on selectedDate: Date, at cafeTime: Date) -> Date? {
        var components = deviceCalendar.dateComponents([.year, .month, .day], from: selectedDate)
        let time = cafeCalendar.dateComponents([.hour, .minute], from: cafeTime)
        components.hour = time.hour
        components.minute = time.minute
        return cafeCalendar.date(from: components)
    }

    static func pickerDate(for timestamp: Date) -> Date {
        var components = cafeCalendar.dateComponents([.year, .month, .day], from: timestamp)
        components.hour = 12
        return deviceCalendar.date(from: components)!
    }

    static func isSameCafeMinute(_ first: Date, _ second: Date) -> Bool {
        let firstTime = cafeCalendar.dateComponents([.hour, .minute], from: first)
        let secondTime = cafeCalendar.dateComponents([.hour, .minute], from: second)
        return firstTime.hour == secondTime.hour && firstTime.minute == secondTime.minute
    }

    static func closingDate(for mealType: MealType, on selectedDate: Date) -> Date? {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = .current
        var cafeCalendar = Calendar(identifier: .gregorian)
        cafeCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let selectedDay = localCalendar.dateComponents([.year, .month, .day], from: selectedDate)
        guard let cafeDay = cafeCalendar.date(from: selectedDay) else { return nil }
        let weekday = cafeCalendar.component(.weekday, from: cafeDay)
        guard let service = mealService(for: mealType, weekday: weekday) else { return nil }

        var closingComponents = cafeCalendar.dateComponents([.year, .month, .day], from: cafeDay)
        closingComponents.hour = service.endMinute / 60
        closingComponents.minute = service.endMinute % 60
        return cafeCalendar.date(from: closingComponents)
    }

    static func status(at date: Date) -> CafeStatus {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let weekday = calendar.component(.weekday, from: date)
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let todaysServices = services(for: weekday)

        if let current = todaysServices.first(where: { minute >= $0.startMinute && minute < $0.endMinute }) {
            return CafeStatus(isOpen: true, headline: "Open now · \(current.name)", detail: current.timeRange)
        }

        if let next = todaysServices.first(where: { minute < $0.startMinute }) {
            return CafeStatus(isOpen: false, headline: "Closed now", detail: "Opens for \(next.name.lowercased()) at \(next.openingTime)")
        }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date)!
        let nextWeekday = calendar.component(.weekday, from: tomorrow)
        let next = services(for: nextWeekday)[0]
        let dayName = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][nextWeekday - 1]
        return CafeStatus(isOpen: false, headline: "Closed now", detail: "Opens \(dayName) at \(next.openingTime)")
    }

    private static func services(for weekday: Int) -> [CafeService] {
        weekday == 1 || weekday == 7 ? weekends : weekdays
    }

    static func mealServices(for weekday: Int) -> [(mealType: MealType, service: CafeService)] {
        MealType.allCases.compactMap { mealType in
            guard let service = mealService(for: mealType, weekday: weekday) else { return nil }
            return (mealType, service)
        }
    }

    private static func mealService(for mealType: MealType, weekday: Int) -> CafeService? {
        let isWeekend = weekday == 1 || weekday == 7
        let serviceName: String
        switch mealType {
        case .breakfast: serviceName = "Breakfast"
        case .lunch: serviceName = isWeekend ? "Brunch" : "Lunch"
        case .dinner: serviceName = isWeekend ? "Late night" : "Dinner"
        }
        return services(for: weekday).first(where: { $0.name == serviceName })
    }
}
