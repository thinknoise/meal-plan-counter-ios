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
    // Regular weekly schedule published by Bon Appétit for CalArts Steve's Café.
    // Special hours and academic breaks can differ from this offline schedule.
    static let sourceURL = URL(string: "https://calarts.cafebonappetit.com/")!

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
}
