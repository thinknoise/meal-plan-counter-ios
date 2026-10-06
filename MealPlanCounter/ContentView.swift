import SwiftUI
import Combine
import UIKit

private enum Palette {
    static let indigo = Color(red: 13 / 255, green: 7 / 255, blue: 140 / 255)
    static let paper = Color(red: 215 / 255, green: 255 / 255, blue: 254 / 255)
    static let cyan = Color(red: 0, green: 1, blue: 1)
    static let lime = Color(red: 0, green: 1, blue: 0)
    static let muted = Color(red: 157 / 255, green: 253 / 255, blue: 255 / 255)
}

private enum Screen {
    case count
    case record
    case settings
}

struct ContentView: View {
    @ObservedObject var store: MealPlanStore
    @ObservedObject var cafeReminder: CafeReminder
    @State private var screen: Screen = .count

    var body: some View {
        ZStack {
            Palette.indigo.ignoresSafeArea()

            if let plan = store.plan {
                VStack(spacing: 0) {
                    Group {
                        switch screen {
                        case .count:
                            CounterView(plan: plan, useMeal: store.useMeal, undoMeal: store.undoLastMeal) {
                                screen = .settings
                            }
                        case .record:
                            RecordView(plan: plan, addMeal: store.addPastMeal,
                                       editMeal: store.editMeal, removeMeal: store.removeMeal)
                        case .settings:
                            SettingsView(store: store, cafeReminder: cafeReminder) { screen = .count }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    bottomBar
                }
            } else {
                SetupView { name, planType, term in
                    store.create(name: name, planType: planType, term: term)
                    screen = .count
                }
            }
        }
        .foregroundStyle(Palette.paper)
        .tint(Palette.cyan)
        .onAppear {
            store.refreshWeeklyReset()
            cafeReminder.refresh()
            if store.plan?.planType == nil && store.plan != nil { screen = .settings }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { date in
            store.refreshWeeklyReset(at: date)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            store.refreshWeeklyReset()
            cafeReminder.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            store.refreshWeeklyReset()
            cafeReminder.refresh()
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            tabButton("COUNT", symbol: "circle.grid.2x2.fill", destination: .count)
            tabButton("MEALS", symbol: "clock", destination: .record)
            tabButton("SETTINGS", symbol: "gearshape", destination: .settings)
        }
        .padding(.top, 13)
        .padding(.bottom, 7)
        .background {
            Palette.paper.ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) { Palette.cyan.frame(height: 2) }
    }

    private func tabButton(_ title: String, symbol: String, destination: Screen) -> some View {
        Button {
            screen = destination
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .bold))
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(Palette.indigo)
            .opacity(screen == destination ? 1 : 0.55)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(screen == destination ? .isSelected : [])
    }
}

private struct SetupView: View {
    let create: (String, MealPlanType, MealPlanTerm) -> Void

    @State private var name = "Bob"
    @State private var selectedPlan: MealPlanType?
    @State private var selectedTerm = MealPlanTerm.containing(.now)
    @State private var showError = false
    @FocusState private var focusedField: Field?

    private enum Field { case name }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    BrandHeader()

                    Text("Meal Plan Counter")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .tracking(-3)
                        .lineSpacing(-8)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 40)

                    Text("A personal counter for the Meal Plan at CalArts.")
                        .font(.system(size: 15, weight: .medium))
                        .lineSpacing(4)
                        .foregroundStyle(Palette.muted)
                        .padding(.top, 23)
                        .padding(.bottom, 44)

                    LabeledInput(label: "YOUR NAME", text: $name, placeholder: "Bob")
                        .focused($focusedField, equals: .name)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }

                    PlanPicker(selection: $selectedPlan)
                        .padding(.top, 20)

                    TermPicker(selection: $selectedTerm)
                        .padding(.top, 20)

                    Text("Weekly plans refill on Sunday at local midnight. The 140 Block Plan counts down during the semester.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .padding(.top, 13)

                    if showError {
                        Text("Enter a name and choose a meal plan.")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Palette.lime)
                            .padding(.top, 12)
                    }

                    ActionButton(title: "Start counting", symbol: "arrow.right") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, let selectedPlan else {
                            showError = true
                            return
                        }
                        focusedField = nil
                        create(trimmed, selectedPlan, selectedTerm)
                    }
                    .padding(.top, 25)

                    Text("NO ACCOUNT NEEDED · SAVED ON THIS IPHONE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Meal counts in this app are tracked locally and are not connected to CalArts’ official dining or campus-card systems.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.paper)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("CalArts Meal Plan Counter is an independent app and is not affiliated with or endorsed by California Institute of the Arts, Bon Appétit, Illumia, or Transact. Meal plans, café hours, and menus may change; check official sources for current information.")
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 40)
                }
                .padding(.horizontal, 27)
                .padding(.top, 18)
                .padding(.bottom, 30)
                .frame(maxWidth: 560)
                .frame(minHeight: geometry.size.height, alignment: .top)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

private struct CounterView: View {
    let plan: MealPlan
    let useMeal: () -> Void
    let undoMeal: () -> Void
    let openSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    BrandHeader()
                    Spacer()
                    Button(action: openSettings) {
                        Text(plan.name)
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 12)
                            .frame(width: min(160, max(55, CGFloat(plan.name.count) * 8 + 24)), height: 55)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.cyan, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open settings for \(plan.name)")
                }

                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    CafeStatusCard(status: CafeHours.status(at: timeline.date))
                }
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: 12) {
                        Text("\(plan.remainingMeals)")
                            .font(.system(size: 100, weight: .black, design: .rounded))
                            .tracking(-7)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                        Eyebrow("MEALS LEFT")
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Rectangle().stroke(Palette.cyan, lineWidth: 2)
                            Rectangle()
                                .fill(Palette.lime)
                                .frame(width: max(0, (proxy.size.width - 8) * plan.fractionUsed))
                                .padding(4)
                        }
                    }
                    .frame(height: 17)
                    .padding(.top, 6)
                    .accessibilityLabel("\(plan.usedMeals) of \(plan.totalMeals) meals used")

                    HStack {
                        Eyebrow("\(plan.usedMeals) USED")
                        Spacer()
                        Eyebrow(plan.planType?.isWeekly == true
                            ? "THIS WEEK: \(plan.totalMeals) MEALS"
                            : "STARTED WITH: \(plan.totalMeals) MEALS")
                    }
                    .padding(.top, 9)

                    if plan.planType?.isWeekly == true {
                        TimelineView(.periodic(from: .now, by: 60)) { timeline in
                            if let days = plan.daysUntilWeeklyReset(after: timeline.date) {
                                Text("\(days) \(days == 1 ? "DAY" : "DAYS") UNTIL SUNDAY RESET")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .tracking(0.5)
                                    .foregroundStyle(Palette.lime)
                            }
                        }
                        .padding(.top, 17)
                    }
                }
                .padding(.vertical, 22)
                .overlay(alignment: .top) { Palette.cyan.frame(height: 2) }
                .overlay(alignment: .bottom) { Palette.cyan.frame(height: 2) }
                .padding(.top, 35)

                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    let hasStarted = timeline.date >= plan.planStartDate
                    ActionButton(title: !hasStarted ? "Plan not started"
                                 : plan.remainingMeals == 0 ? "All meals used" : "Use 1 meal",
                                 symbol: "plus", isEnabled: hasStarted && plan.remainingMeals > 0) {
                        withAnimation(.easeOut(duration: 0.2)) { useMeal() }
                    }
                }
                .padding(.top, 30)

                if plan.canUndoLastMeal {
                    Button(action: undoMeal) {
                        Text("UNDO LAST MEAL")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .underline()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 19)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("TAP ONCE AFTER YOU CHECK OUT")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 17)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 30)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct RecordView: View {
    let plan: MealPlan
    let addMeal: (MealType, Date) -> Bool
    let editMeal: (UUID, MealType, Date) -> Bool
    let removeMeal: (UUID) -> Bool

    @State private var showingAddMeal = false
    @State private var editingRecord: MealRecord?

    private var displayedRecords: [MealRecord] {
        plan.records.enumerated().sorted { left, right in
            let leftDate = plan.displayDate(for: left.element)
            let rightDate = plan.displayDate(for: right.element)
            return leftDate == rightDate ? left.offset > right.offset : leftDate > rightDate
        }.map { $0.element }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    BrandHeader()
                    Spacer()
                    HeaderTitle("Meals")
                }

                Text("A history of your plan balance, saved on this iPhone.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 24)

                if let weekStart = plan.currentWeeklyStart(at: .now) {
                    Eyebrow("THIS WEEK STARTED")
                        .foregroundStyle(Palette.cyan)
                        .padding(.top, 22)
                    Text(RecordRow.dayDateText(weekStart))
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.top, 6)
                } else if plan.planType == .block140 {
                    Eyebrow("SEMESTER START")
                        .foregroundStyle(Palette.cyan)
                        .padding(.top, 22)
                    Text(RecordRow.dayDateText(plan.planStartDate,
                                               timeZone: TimeZone(identifier: "America/Los_Angeles")!))
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.top, 6)
                }

                if let reset = plan.nextWeeklyReset(after: .now) {
                    Eyebrow("NEXT WEEKLY RESET")
                        .foregroundStyle(Palette.cyan)
                        .padding(.top, 17)
                    Text(RecordRow.resetDateText(reset))
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.top, 6)
                }

                if plan.planType != nil {
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        if plan.planStartDate <= timeline.date {
                            Button { showingAddMeal = true } label: {
                                Label("ADD MEAL", systemImage: "plus")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .tracking(0.7)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 49)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.cyan, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 24)
                }

                HStack(alignment: .firstTextBaseline) {
                    Eyebrow("ACTIVITY")
                    Spacer()
                    Eyebrow("MEALS LEFT")
                }
                .foregroundStyle(Palette.cyan)
                .padding(.top, 35)
                .padding(.bottom, 12)

                LazyVStack(spacing: 0) {
                    ForEach(displayedRecords) { record in
                        if record.kind == .used {
                            Button { editingRecord = record } label: {
                                RecordRow(record: record)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Edit or remove meal")
                        } else {
                            RecordRow(record: record,
                                      startDate: record.kind == .started || plan.isTermStart(record)
                                          ? plan.displayDate(for: record) : nil,
                                      isTermStart: plan.isTermStart(record),
                                      startTimeZone: TimeZone(identifier: "America/Los_Angeles")!)
                        }
                    }
                }

                if plan.records.contains(where: { $0.kind == .imported }) {
                    Text("This balance was saved before meal history was available. Earlier meal uses have no individual timestamps.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 22)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 35)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showingAddMeal) {
            AddMealSheet(isWeekly: plan.planType?.isWeekly == true,
                         earliestDate: plan.planStartDate, addMeal: addMeal)
        }
        .sheet(item: $editingRecord) { record in
            EditMealSheet(record: record,
                          editableDates: plan.editableDateRange(for: record.id) ?? record.timestamp...record.timestamp,
                          isWeekly: plan.isWeeklyPeriod(for: record.id),
                          editMeal: editMeal, removeMeal: removeMeal)
        }
    }
}

private struct RecordRow: View {
    let record: MealRecord
    var startDate: Date? = nil
    var isTermStart = false
    var startTimeZone: TimeZone = .current

    private var title: String {
        switch record.kind {
        case .started: "Meal plan started"
        case .used: "\(Self.format(record.timestamp, as: "EEEE, MMM d")) · \(record.mealType?.rawValue ?? "Unassigned")"
        case .adjusted: isTermStart ? "\(record.planTerm?.title ?? "Meal plan") term started" : "Plan updated"
        case .imported: "Starting balance"
        case .reset: "Week reset"
        }
    }

    private var dateText: String? {
        if record.kind == .used || record.kind == .imported { return nil }
        if record.kind == .started || isTermStart {
            return Self.dayDateText(startDate ?? record.timestamp, timeZone: startTimeZone)
        }
        return record.timestamp.formatted(.dateTime.year().month(.abbreviated).day().hour().minute())
    }

    private var entryText: String? {
        guard record.kind == .used else { return nil }
        let action = record.lastAction ?? (record.recordedAt == nil ? .tapped
            : record.tappedAt == nil ? .added : .edited)
        let actionDate = action == .tapped
            ? record.tappedAt ?? record.timestamp : record.recordedAt ?? record.timestamp
        let pattern = Calendar.current.isDate(actionDate, inSameDayAs: record.timestamp)
            ? "h:mm a" : "EEE, MMM d, h:mm a"
        return "\(action.rawValue.capitalized): \(Self.format(actionDate, as: pattern))"
    }

    private var accessibilityText: String {
        [title, dateText, entryText, "\(displayedRemainingMeals) meals left"]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private var displayedRemainingMeals: Int {
        record.kind == .started || isTermStart
            ? record.startingAllowance ?? record.remainingMeals : record.remainingMeals
    }

    static func resetDateText(_ date: Date) -> String {
        format(date, as: "EEEE, MMM d, yyyy 'at' h:mm a")
    }

    static func dayDateText(_ date: Date, timeZone: TimeZone = .current) -> String {
        format(date, as: "EEEE, MMM d, yyyy", timeZone: timeZone)
    }

    private static func format(_ date: Date, as pattern: String, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                if let dateText {
                    Text(dateText)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                }
                if let entryText {
                    Text(entryText)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                }
            }
            Spacer(minLength: 4)
            if record.kind == .used {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.cyan)
                    .accessibilityHidden(true)
            }
            Text("\(displayedRemainingMeals)")
                .font(.system(size: 29, weight: .black, design: .rounded))
                .foregroundStyle(Palette.lime)
                .monospacedDigit()
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) { Palette.cyan.frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

private struct AddMealSheet: View {
    @Environment(\.dismiss) private var dismiss
    let isWeekly: Bool
    let earliestDate: Date
    let addMeal: (MealType, Date) -> Bool

    @State private var mealType = MealType.inferred(at: .now)
    @State private var mealDate = Date()
    @State private var errorMessage = ""
    @State private var showingDatePicker = false

    private var dateRange: ClosedRange<Date> {
        earliestDate...Date()
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: mealDate)
    }

    private var closingTimeText: String? {
        guard let closingDate = CafeHours.closingDate(for: mealType, on: mealDate) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: closingDate)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Add Meal")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                    Spacer()
                    Button("CANCEL") { dismiss() }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }

                Text("Record a meal you forgot to count. Choose the meal and date.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 12)

                Eyebrow("MEAL")
                    .foregroundStyle(Palette.cyan)
                    .padding(.top, 28)
                Picker("Meal type", selection: $mealType) {
                    ForEach(MealType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.top, 10)

                Eyebrow("DATE")
                    .foregroundStyle(Palette.cyan)
                    .padding(.top, 27)
                Button { showingDatePicker = true } label: {
                    HStack {
                        Text(dateText)
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                        Image(systemName: "calendar")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 55)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.cyan, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Meal date, \(dateText)")
                .padding(.top, 10)

                if let closingTimeText {
                    Text("Recorded at the café’s regular \(closingTimeText) closing time. Holidays may differ.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .padding(.top, 11)
                }

                Text("Choose a date on or after \(RecordRow.dayDateText(earliestDate, timeZone: TimeZone(identifier: "America/Los_Angeles")!)).")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 5)

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.lime)
                        .padding(.top, 17)
                }

                ActionButton(title: "Add meal", symbol: "plus") {
                    guard let closingDate = CafeHours.closingDate(for: mealType, on: mealDate) else {
                        errorMessage = "There is no closing time for this meal."
                        return
                    }
                    guard closingDate >= earliestDate else {
                        errorMessage = "Choose a date on or after the meal plan start."
                        return
                    }
                    guard closingDate <= .now else {
                        errorMessage = "Add this meal after its café closing time."
                        return
                    }
                    if addMeal(mealType, closingDate) {
                        dismiss()
                    } else {
                        errorMessage = "There are no available meals left for that week or block."
                    }
                }
                .padding(.top, 27)
            }
            .padding(24)
        }
        .foregroundStyle(Palette.paper)
        .background(Palette.indigo)
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showingDatePicker) {
            MealDatePickerSheet(selectedDate: $mealDate, allowedDates: dateRange,
                                isWeekly: isWeekly)
        }
    }
}

private struct EditMealSheet: View {
    @Environment(\.dismiss) private var dismiss
    let record: MealRecord
    let editableDates: ClosedRange<Date>
    let isWeekly: Bool
    let editMeal: (UUID, MealType, Date) -> Bool
    let removeMeal: (UUID) -> Bool

    @State private var mealType: MealType = .lunch
    @State private var mealDate = Date()
    @State private var errorMessage = ""
    @State private var showingDatePicker = false
    @State private var showingRemoveConfirmation = false

    private var dateRange: ClosedRange<Date> {
        Calendar.current.startOfDay(for: editableDates.lowerBound)...editableDates.upperBound
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: mealDate)
    }

    private var usesClosingTime: Bool {
        !Calendar.current.isDate(mealDate, inSameDayAs: record.timestamp)
    }

    private var closingTimeText: String? {
        guard usesClosingTime,
              let closingDate = CafeHours.closingDate(for: mealType, on: mealDate) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: closingDate)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Edit Meal")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                    Spacer()
                    Button("CANCEL") { dismiss() }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }

                Text("Change the meal type or date, or remove this meal from your record.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 13)

                Eyebrow("MEAL TYPE")
                    .foregroundStyle(Palette.cyan)
                    .padding(.top, 29)
                Picker("Meal type", selection: $mealType) {
                    ForEach(MealType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.top, 10)

                Eyebrow("DATE")
                    .foregroundStyle(Palette.cyan)
                    .padding(.top, 27)
                Button { showingDatePicker = true } label: {
                    HStack {
                        Text(dateText)
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                        Image(systemName: "calendar")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 55)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.cyan, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Meal date, \(dateText)")
                .padding(.top, 10)

                if let closingTimeText {
                    Text("The changed meal will use the café’s regular \(closingTimeText) closing time. Holidays may differ.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .padding(.top, 11)
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.lime)
                        .padding(.top, 17)
                }

                ActionButton(title: "Save meal", symbol: "checkmark", action: save)
                    .padding(.top, 30)

                Button("REMOVE MEAL", role: .destructive) {
                    showingRemoveConfirmation = true
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .underline()
                .foregroundStyle(Palette.paper)
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
            }
            .padding(24)
        }
        .foregroundStyle(Palette.paper)
        .background(Palette.indigo)
        .presentationDetents([.large])
        .onAppear {
            mealType = record.mealType ?? MealType.inferred(at: record.timestamp)
            mealDate = record.timestamp
        }
        .sheet(isPresented: $showingDatePicker) {
            MealDatePickerSheet(selectedDate: $mealDate, allowedDates: dateRange,
                                isWeekly: isWeekly)
        }
        .confirmationDialog("Remove this meal?", isPresented: $showingRemoveConfirmation) {
            Button("Remove meal", role: .destructive) {
                if removeMeal(record.id) {
                    dismiss()
                } else {
                    errorMessage = "This meal could not be removed."
                }
            }
        } message: {
            Text("The meal will be deleted and its affected balance updated.")
        }
    }

    private func save() {
        let timestamp: Date
        if usesClosingTime {
            guard let closingDate = CafeHours.closingDate(for: mealType, on: mealDate) else {
                errorMessage = "There is no closing time for this meal."
                return
            }
            guard editableDates.contains(closingDate) else {
                errorMessage = "Choose a meal date within this plan period."
                return
            }
            guard closingDate <= .now else {
                errorMessage = "Save this meal after its café closing time."
                return
            }
            timestamp = closingDate
        } else {
            timestamp = record.timestamp
        }
        if editMeal(record.id, mealType, timestamp) {
            dismiss()
        } else {
            errorMessage = "That week or block has no available meals for this date."
        }
    }
}

private struct MealDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDate: Date
    let allowedDates: ClosedRange<Date>
    let isWeekly: Bool

    @State private var displayedWeekStart = Date()

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 1
        return calendar
    }

    private var firstAllowedDay: Date { calendar.startOfDay(for: allowedDates.lowerBound) }
    private var lastAllowedDay: Date { calendar.startOfDay(for: allowedDates.upperBound) }

    private var canShowPreviousWeek: Bool {
        calendar.date(byAdding: .day, value: -1, to: displayedWeekStart)! >= firstAllowedDay
    }

    private var canShowNextWeek: Bool {
        calendar.date(byAdding: .day, value: 7, to: displayedWeekStart)! <= lastAllowedDay
    }

    private var weekLabel: String {
        let saturday = calendar.date(byAdding: .day, value: 6, to: displayedWeekStart)!
        return "\(Self.format(displayedWeekStart, as: "MMM d")) – \(Self.format(saturday, as: "MMM d, yyyy"))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Choose Date")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                    Spacer()
                    Button("DONE") { dismiss() }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }

                if isWeekly {
                    weeklyPicker
                        .padding(.top, 24)
                } else {
                    DatePicker("Meal date", selection: $selectedDate,
                               in: allowedDates, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .colorScheme(.dark)
                        .padding(.top, 19)
                }
            }
            .padding(24)
        }
        .foregroundStyle(Palette.paper)
        .background(Palette.indigo)
        .presentationDetents([.medium, .large])
        .onAppear { displayedWeekStart = weekStart(for: selectedDate) }
    }

    private var weeklyPicker: some View {
        VStack(spacing: 16) {
            HStack {
                Button {
                    displayedWeekStart = calendar.date(byAdding: .day, value: -7, to: displayedWeekStart)!
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 32, height: 44)
                }
                .disabled(!canShowPreviousWeek)
                .opacity(canShowPreviousWeek ? 1 : 0.35)
                .accessibilityLabel("Previous week")

                Spacer(minLength: 2)
                Text(weekLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                Spacer(minLength: 2)

                Button {
                    displayedWeekStart = calendar.date(byAdding: .day, value: 7, to: displayedWeekStart)!
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 32, height: 44)
                }
                .disabled(!canShowNextWeek)
                .opacity(canShowNextWeek ? 1 : 0.35)
                .accessibilityLabel("Next week")
            }

            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { offset in
                    let day = calendar.date(byAdding: .day, value: offset, to: displayedWeekStart)!
                    let selected = calendar.isDate(day, inSameDayAs: selectedDate)
                    let selectable = day >= firstAllowedDay && day <= lastAllowedDay
                    Button { selectedDate = day } label: {
                        VStack(spacing: 6) {
                            Text(Self.format(day, as: "EEE").uppercased())
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                            Text("\(calendar.component(.day, from: day))")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .foregroundStyle(selected ? Palette.indigo : Palette.paper)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selected ? Palette.cyan : Color.clear)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.cyan, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(!selectable)
                    .opacity(selectable ? 1 : 0.35)
                    .accessibilityLabel(Self.format(day, as: "EEEE, MMMM d, yyyy"))
                    .accessibilityValue(selected ? "Selected" : "")
                }
            }
        }
    }

    private func weekStart(for date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        let daysSinceSunday = calendar.component(.weekday, from: day) - 1
        return calendar.date(byAdding: .day, value: -daysSinceSunday, to: day)!
    }

    private static func format(_ date: Date, as pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

private struct CafeStatusCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let status: CafeStatus
    @State private var showingHours = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow("STEVE’S CAFÉ")
                    Text(status.headline)
                        .font(.system(size: 17, weight: .heavy))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                Image(systemName: status.isOpen ? "checkmark.circle.fill" : "clock.fill")
                    .font(.system(size: 22, weight: .bold))
                    .accessibilityHidden(true)
            }

            Text(status.detail)
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 8)

            HStack(spacing: 12) {
                Button("VIEW HOURS") { showingHours = true }
                Spacer(minLength: 0)
                Link("TODAY’S MENU ↗", destination: CafeHours.sourceURL)
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .underline()
            .padding(.top, 13)

            Text("REGULAR HOURS · HOLIDAYS MAY DIFFER")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.3)
                .padding(.top, 11)
        }
        .foregroundStyle(Palette.indigo)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if status.isOpen {
                if reduceMotion { Palette.lime }
                else { MovingCafeBanner() }
            } else {
                Palette.cyan
            }
        }
        .sheet(isPresented: $showingHours) { CafeHoursSheet() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Steve's Café, \(status.headline), \(status.detail). Based on regular hours; holidays may differ.")
    }
}

private struct MovingCafeBanner: View {
    @State private var sweepRight = false

    var body: some View {
        GeometryReader { geometry in
            Palette.lime
                .overlay {
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.26), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.9)
                    .offset(x: sweepRight ? geometry.size.width * 0.5 : -geometry.size.width * 0.5)
                    .animation(.linear(duration: 12).repeatForever(autoreverses: false), value: sweepRight)
                }
                .clipped()
        }
        .onAppear { sweepRight = true }
    }
}

private struct CafeHoursSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Steve’s Café")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                    Spacer()
                    Button("DONE") { dismiss() }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .padding(.bottom, 27)

                serviceList("MON–FRI", services: CafeHours.weekdays)
                serviceList("SAT–SUN", services: CafeHours.weekends)
                    .padding(.top, 26)

                Text("Regular weekly hours in Los Angeles time. Holidays and academic breaks may change service.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 28)

                Link("CHECK TODAY’S HOURS & MENU ↗", destination: CafeHours.sourceURL)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Palette.lime)
                    .padding(.top, 16)
            }
            .padding(24)
        }
        .foregroundStyle(Palette.paper)
        .background(Palette.indigo)
        .presentationDetents([.medium, .large])
    }

    private func serviceList(_ heading: String, services: [CafeService]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(heading)
                .foregroundStyle(Palette.cyan)
                .padding(.bottom, 10)
            ForEach(services, id: \.name) { service in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(service.name)
                        .font(.system(size: 14, weight: .bold))
                    Spacer(minLength: 8)
                    Text(service.timeRange)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Palette.cyan.opacity(0.5).frame(height: 1) }
            }
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var store: MealPlanStore
    @ObservedObject var cafeReminder: CafeReminder
    let goBack: () -> Void

    @State private var name = ""
    @State private var selectedPlan: MealPlanType?
    @State private var selectedTerm = MealPlanTerm.containing(.now)
    @State private var showingClearConfirmation = false
    @State private var showingReminderExplanation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    BrandHeader()
                    Spacer()
                    HeaderTitle("Settings")
                }

                Text("Choose your CalArts plan. Each tap uses one meal, and the count stays on this iPhone.")
                    .font(.system(size: 15, weight: .medium))
                    .lineSpacing(4)
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 24)
                    .padding(.bottom, 33)

                LabeledInput(label: "YOUR NAME", text: $name, placeholder: "Bob")
                    .textContentType(.givenName)
                    .onChange(of: name) { _, newName in store.updateName(newName) }

                Text("Name saves as you type.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 9)

                PlanPicker(selection: $selectedPlan)
                    .padding(.top, 25)

                TermPicker(selection: $selectedTerm)
                    .padding(.top, 25)

                Text(planExplanation)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 13)

                ActionButton(title: "Save changes", symbol: "checkmark",
                             isEnabled: planSettingsChanged, action: save)
                .padding(.top, 31)

                Eyebrow("REMINDERS")
                    .foregroundStyle(Palette.cyan)
                    .padding(.top, 42)

                reminderSetting(
                    "Steve's Café Location Reminder",
                    detail: "Remind me when I arrive at Steve's.",
                    isOn: Binding(
                        get: { cafeReminder.isEnabled },
                        set: { enabled in
                            if enabled { showingReminderExplanation = true }
                            else { cafeReminder.disable() }
                        }
                    ),
                    status: cafeReminder.isEnabled ? cafeReminder.statusMessage : nil
                )

                reminderSetting(
                    "Meal Time Reminders",
                    detail: "Let me know when each meal begins.",
                    isOn: Binding(
                        get: { cafeReminder.isMealTimeEnabled },
                        set: cafeReminder.setMealTimeEnabled
                    ),
                    status: cafeReminder.isMealTimeEnabled ? cafeReminder.mealTimeStatusMessage : nil
                )

                reminderSetting(
                    "Closing Soon Reminders",
                    detail: "Remind me 20 minutes before a meal period ends.",
                    isOn: Binding(
                        get: { cafeReminder.isClosingSoonEnabled },
                        set: cafeReminder.setClosingSoonEnabled
                    ),
                    status: cafeReminder.isClosingSoonEnabled ? cafeReminder.closingSoonStatusMessage : nil
                )

                Text("Based on regular café hours. Holidays and academic breaks may differ.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 18)

                if cafeReminder.needsAnySystemSettings,
                   let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    Link("OPEN IPHONE SETTINGS ↗", destination: settingsURL)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .underline()
                        .foregroundStyle(Palette.cyan)
                        .padding(.top, 12)
                }

                Button("CLEAR EVERYTHING FROM THIS IPHONE", role: .destructive) {
                    showingClearConfirmation = true
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .underline()
                .foregroundStyle(Palette.paper)
                .padding(.top, 48)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Meal counts in this app are tracked locally and are not connected to CalArts’ official dining or campus-card systems.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.paper)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("CalArts Meal Plan Counter is an independent app and is not affiliated with or endorsed by California Institute of the Arts, Bon Appétit, Illumia, or Transact. Meal plans, café hours, and menus may change; check official sources for current information.")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 32)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 35)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear(perform: loadFields)
        .alert("Steve's Café Reminder", isPresented: $showingReminderExplanation) {
            Button("Not now", role: .cancel) {}
            Button("Continue") { cafeReminder.enable() }
        } message: {
            Text("Meal Plan Counter can remind you to count your meal when you arrive at Steve's Café. Choose Precise Location for the 30-meter reminder. The app does not save or send your location.")
        }
        .confirmationDialog("Start all over on this iPhone?", isPresented: $showingClearConfirmation) {
            Button("Clear everything and start over", role: .destructive) {
                cafeReminder.clear()
                store.clear()
            }
        } message: {
            Text("Your saved plan, meal count, meal record, and reminder settings will be deleted from this iPhone. You'll return to setup.")
        }
    }

    private func reminderSetting(_ title: String, detail: String,
                                 isOn: Binding<Bool>, status: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: isOn) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(Palette.lime)

            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.muted)

            if let status {
                Text(status)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(.top, 20)
    }

    private func loadFields() {
        guard let plan = store.plan else { return }
        name = plan.name
        selectedPlan = plan.planType
        selectedTerm = plan.planTerm
    }

    private var planSettingsChanged: Bool {
        guard let plan = store.plan, let selectedPlan else { return false }
        return selectedPlan != plan.planType || selectedTerm != plan.planTerm
    }

    private var planExplanation: String {
        guard let selectedPlan else {
            return "Choose a plan to replace the old custom count and start at its full allowance."
        }
        let resetNote = selectedPlan.isWeekly
            ? "Weekly meals run Sunday through Saturday. Unused meals expire, and the count refills Sunday at local midnight."
            : "The 140 meals count down through the semester."
        return selectedPlan == store.plan?.planType && selectedTerm == store.plan?.planTerm
            ? resetNote
            : resetNote + " Changing the plan or term starts a new count at the full allowance."
    }

    private func save() {
        guard planSettingsChanged, let selectedPlan, let savedName = store.plan?.name else { return }
        store.updateSettings(name: savedName, planType: selectedPlan, term: selectedTerm)
        goBack()
    }
}

private struct BrandHeader: View {
    var body: some View {
        Image("CalArtsLogo")
            .resizable()
            .renderingMode(.original)
            .aspectRatio(contentMode: .fit)
            .frame(width: 144, height: 55, alignment: .leading)
            .accessibilityLabel("CalArts")
    }
}

private struct HeaderTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .padding(.horizontal, 12)
            .frame(height: 55)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.cyan, lineWidth: 2))
    }
}

private struct Eyebrow: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.1)
    }
}

private struct PlanPicker: View {
    @Binding var selection: MealPlanType?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("CALARTS MEAL PLAN")
            Picker("CalArts Meal Plan", selection: $selection) {
                if selection == nil {
                    Text("Choose a plan").tag(nil as MealPlanType?)
                }
                ForEach(MealPlanType.allCases) { plan in
                    Text(plan.title).tag(Optional(plan))
                }
            }
            .pickerStyle(.menu)
            .font(.system(size: 16, weight: .semibold))
            .tint(Palette.paper)
            .frame(maxWidth: .infinity, minHeight: 55, alignment: .leading)
            .padding(.horizontal, 16)
            .overlay(Rectangle().stroke(Palette.cyan, lineWidth: 2))
        }
    }
}

private struct TermPicker: View {
    @Binding var selection: MealPlanTerm

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("MEAL PLAN TERM")
            Picker("Meal Plan Term", selection: $selection) {
                ForEach(MealPlanTerm.allCases) { term in
                    Text(term.title).tag(term)
                }
            }
            .pickerStyle(.menu)
            .font(.system(size: 16, weight: .semibold))
            .tint(Palette.paper)
            .frame(maxWidth: .infinity, minHeight: 55, alignment: .leading)
            .padding(.horizontal, 16)
            .overlay(Rectangle().stroke(Palette.cyan, lineWidth: 2))

            Text("Meal plan begins \(RecordRow.dayDateText(selection.startDate, timeZone: TimeZone(identifier: "America/Los_Angeles")!)).")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct LabeledInput: View {
    let label: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(label)
            TextField(placeholder, text: $text)
                .font(.system(size: 16, weight: .semibold))
                .padding(.horizontal, 16)
                .frame(height: 55)
                .overlay(Rectangle().stroke(Palette.cyan, lineWidth: 2))
                .textInputAutocapitalization(label == "YOUR NAME" ? .words : .never)
                .autocorrectionDisabled()
        }
    }
}

private struct ActionButton: View {
    let title: String
    let symbol: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .heavy))
                Spacer()
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .bold))
            }
            .foregroundStyle(Palette.indigo)
            .padding(.horizontal, 21)
            .frame(height: 61)
            .background(isEnabled ? Palette.lime : Palette.muted)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
