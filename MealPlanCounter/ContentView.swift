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
                SetupView { name, planType in
                    store.create(name: name, planType: planType)
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
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            tabButton("COUNT", symbol: "circle.grid.2x2.fill", destination: .count)
            tabButton("RECORD", symbol: "clock", destination: .record)
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
    let create: (String, MealPlanType) -> Void

    @State private var name = "Bob"
    @State private var selectedPlan: MealPlanType?
    @State private var showError = false
    @FocusState private var focusedField: Field?

    private enum Field { case name }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    BrandHeader()

                    Eyebrow("MEAL PLAN COUNTER")
                        .padding(.top, 40)
                    Text("Meal Plan Counter")
                        .font(.system(size: 56, weight: .black, design: .rounded))
                        .tracking(-3)
                        .lineSpacing(-8)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 15)

                    Text("A personal count of the meals in your plan. Kept right here on your iPhone.")
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
                        create(trimmed, selectedPlan)
                    }
                    .padding(.top, 25)

                    Text("NO ACCOUNT NEEDED · SAVED ON THIS IPHONE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
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
                    Eyebrow("MEALS LEFT")
                    Text("\(plan.remainingMeals)")
                        .font(.system(size: 100, weight: .black, design: .rounded))
                        .tracking(-7)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .padding(.top, 2)

                    HStack(alignment: .bottom) {
                        Eyebrow(plan.planType?.isWeekly == true
                            ? "THIS WEEK: \(plan.totalMeals) MEALS"
                            : "STARTED WITH: \(plan.totalMeals) MEALS")
                        Spacer()
                        Text("\(plan.usedMeals) USED")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
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
                    .padding(.top, 26)
                    .accessibilityLabel("\(plan.usedMeals) of \(plan.totalMeals) meals used")

                    HStack {
                        Eyebrow("\(plan.usedMeals) USED")
                        Spacer()
                        Eyebrow("\(Int((plan.fractionUsed * 100).rounded()))% COMPLETE")
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

                ActionButton(title: plan.remainingMeals == 0 ? "All meals used" : "Use 1 meal", symbol: "plus", isEnabled: plan.remainingMeals > 0) {
                    withAnimation(.easeOut(duration: 0.2)) { useMeal() }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BrandHeader()

                Text("Meal record")
                    .font(.system(size: 39, weight: .black, design: .rounded))
                    .tracking(-2)
                    .padding(.top, 28)

                Text("A history of your plan balance, saved on this iPhone.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 10)

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
                    Text(plan.semesterStartDate.map {
                        RecordRow.dayDateText($0, timeZone: TimeZone(identifier: "America/Los_Angeles")!)
                    } ?? "Set the date in Settings")
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
                    Button { showingAddMeal = true } label: {
                        Label("ADD MEAL", systemImage: "plus")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(0.7)
                            .frame(maxWidth: .infinity)
                            .frame(height: 49)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.cyan, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
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
                    ForEach(plan.records.reversed()) { record in
                        if record.kind == .used {
                            Button { editingRecord = record } label: {
                                RecordRow(record: record)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Edit or remove meal")
                        } else {
                            RecordRow(record: record)
                        }
                    }
                }

                if plan.records.first?.kind == .imported {
                    Text("This plan was set up before meal records were added. Earlier meal uses have no saved timestamps. The first entry shows the balance when recording began.")
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
            AddMealSheet(earliestDate: plan.currentPlanStart,
                         isWeekly: plan.planType?.isWeekly == true, addMeal: addMeal)
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

    private var title: String {
        switch record.kind {
        case .started: "Tracking started"
        case .used: "\(Self.format(record.timestamp, as: "EEEE")) · \(record.mealType?.rawValue ?? "Unassigned")"
        case .adjusted: "Plan updated"
        case .imported: "Record started"
        case .reset: "Week reset"
        }
    }

    private var dateText: String {
        if record.kind == .used {
            return Self.format(record.timestamp, as: "h:mm a")
        }
        if record.kind == .started {
            return Self.dayDateText(record.timestamp)
        }
        return record.timestamp.formatted(.dateTime.year().month(.abbreviated).day().hour().minute())
    }

    private var entryText: String? {
        guard record.kind == .used else { return nil }
        if let recordedAt = record.recordedAt {
            return "Recorded: \(Self.format(recordedAt, as: "EEE, MMM d, yyyy 'at' h:mm a"))"
        }
        // Earlier records have no action timestamp; treat their meal time as a tap.
        return "Tapped: \(Self.format(record.tappedAt ?? record.timestamp, as: "EEE, MMM d, yyyy 'at' h:mm a"))"
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
                Text(dateText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.muted)
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
            Text("\(record.remainingMeals)")
                .font(.system(size: 29, weight: .black, design: .rounded))
                .foregroundStyle(Palette.lime)
                .monospacedDigit()
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) { Palette.cyan.frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(dateText), \(entryText.map { $0 + ", " } ?? "")\(record.remainingMeals) meals left")
    }
}

private struct AddMealSheet: View {
    @Environment(\.dismiss) private var dismiss
    let earliestDate: Date
    let isWeekly: Bool
    let addMeal: (MealType, Date) -> Bool

    @State private var mealType = MealType.inferred(at: .now)
    @State private var mealDate = Date()
    @State private var errorMessage = ""
    @State private var showingDatePicker = false

    private var dateRange: ClosedRange<Date> {
        Calendar.current.startOfDay(for: earliestDate)...Date()
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

                Text("Choose a date from when this plan began through today.")
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
                        errorMessage = "This meal closed before the current plan began."
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
        !Calendar.current.isDate(mealDate, inSameDayAs: record.timestamp) ||
            (record.recordedAt != nil && record.tappedAt == nil && mealType != record.mealType)
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
                        colors: [.clear, .white.opacity(0.12), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.65)
                    .offset(x: sweepRight ? geometry.size.width * 0.85 : -geometry.size.width * 0.85)
                    .animation(.linear(duration: 10).repeatForever(autoreverses: false), value: sweepRight)
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
    @State private var semesterStartDate: Date?
    @State private var errorMessage = ""
    @State private var showingClearConfirmation = false
    @State private var showingReminderExplanation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BrandHeader()

                Text("Meal Plan Settings")
                    .font(.system(size: 39, weight: .black, design: .rounded))
                    .tracking(-2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.top, 28)

                Text("Choose your CalArts plan. Each tap uses one meal, and the count stays on this iPhone.")
                    .font(.system(size: 15, weight: .medium))
                    .lineSpacing(4)
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 13)
                    .padding(.bottom, 33)

                LabeledInput(label: "YOUR NAME", text: $name, placeholder: "Bob")
                    .textContentType(.givenName)

                PlanPicker(selection: $selectedPlan)
                    .padding(.top, 25)

                if selectedPlan == .block140 {
                    SemesterStartInput(date: $semesterStartDate)
                        .padding(.top, 25)
                }

                Text(planExplanation)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 13)

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.lime)
                        .padding(.top, 14)
                }

                ActionButton(title: "Save changes", symbol: "checkmark", action: save)
                .padding(.top, 31)

                Eyebrow("REMINDERS")
                    .foregroundStyle(Palette.cyan)
                    .padding(.top, 42)

                Toggle(isOn: Binding(
                    get: { cafeReminder.isEnabled },
                    set: { enabled in
                        if enabled { showingReminderExplanation = true }
                        else { cafeReminder.disable() }
                    }
                )) {
                    Text("Steve's Café Reminder")
                        .font(.system(size: 16, weight: .bold))
                }
                .tint(Palette.lime)
                .padding(.top, 13)

                Text(cafeReminder.statusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 8)

                if cafeReminder.needsSystemSettings,
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
            Text("Your saved plan, meal count, meal record, and café reminder setting will be deleted from this iPhone. You'll return to setup.")
        }
    }

    private func loadFields() {
        guard let plan = store.plan else { return }
        name = plan.name
        selectedPlan = plan.planType
        semesterStartDate = plan.semesterStartDate
        errorMessage = ""
    }

    private var planExplanation: String {
        guard let selectedPlan else {
            return "Choose a plan to replace the old custom count and start at its full allowance."
        }
        let resetNote = selectedPlan.isWeekly
            ? "Weekly meals run Sunday through Saturday. Unused meals expire, and the count refills Sunday at local midnight."
            : "The 140 meals count down through the semester."
        return selectedPlan == store.plan?.planType
            ? resetNote
            : resetNote + " Changing plans starts a new count at the full allowance."
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let selectedPlan else {
            errorMessage = "Enter a name and choose a meal plan."
            return
        }
        store.updateSettings(name: trimmed, planType: selectedPlan,
                             semesterStartDate: selectedPlan == .block140 ? semesterStartDate : nil)
        goBack()
    }
}

private struct SemesterStartInput: View {
    @Binding var date: Date?
    @State private var pickerDate = Date()
    @State private var showingPicker = false

    private var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private var cafeCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private var dateText: String {
        guard let date else { return "Choose semester start" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = cafeCalendar.timeZone
        formatter.dateFormat = "EEEE, MMM d, yyyy"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("SEMESTER START")
            Button(action: openPicker) {
                HStack {
                    Text(dateText)
                        .font(.system(size: 16, weight: .semibold))
                    Spacer(minLength: 6)
                    Image(systemName: "calendar")
                        .font(.system(size: 17, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .frame(height: 55)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.cyan, lineWidth: 2))
            }
            .buttonStyle(.plain)

            Text("Shown in Record for the 140 Block Plan. Changing this date does not reset meals.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.muted)
        }
        .sheet(isPresented: $showingPicker) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Semester Start")
                            .font(.system(size: 29, weight: .black, design: .rounded))
                        Spacer()
                        Button("DONE", action: savePickerDate)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }

                    DatePicker("Semester start date", selection: $pickerDate,
                               in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .colorScheme(.dark)
                        .padding(.top, 19)
                }
                .padding(24)
            }
            .foregroundStyle(Palette.paper)
            .background(Palette.indigo)
            .presentationDetents([.medium, .large])
        }
    }

    private func openPicker() {
        if let date {
            let day = cafeCalendar.dateComponents([.year, .month, .day], from: date)
            pickerDate = localCalendar.date(from: day) ?? .now
        } else {
            pickerDate = .now
        }
        showingPicker = true
    }

    private func savePickerDate() {
        let day = localCalendar.dateComponents([.year, .month, .day], from: pickerDate)
        date = cafeCalendar.date(from: day)
        showingPicker = false
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
