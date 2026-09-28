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
                            RecordView(plan: plan)
                        case .settings:
                            SettingsView(store: store) { screen = .count }
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
            if store.plan?.planType == nil && store.plan != nil { screen = .settings }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { date in
            store.refreshWeeklyReset(at: date)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            store.refreshWeeklyReset()
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
                        RecordRow(record: record)
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
    }
}

private struct RecordRow: View {
    let record: MealRecord

    private var title: String {
        switch record.kind {
        case .started: "Plan started"
        case .used: "Meal used"
        case .adjusted: "Plan updated"
        case .imported: "Record started"
        case .reset: "Week reset"
        }
    }

    private var dateText: String {
        record.timestamp.formatted(.dateTime.year().month(.abbreviated).day().hour().minute())
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                Text(dateText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 4)
            Text("\(record.remainingMeals)")
                .font(.system(size: 29, weight: .black, design: .rounded))
                .foregroundStyle(Palette.lime)
                .monospacedDigit()
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) { Palette.cyan.frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(dateText), \(record.remainingMeals) meals left")
    }
}

private struct CafeStatusCard: View {
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
        .background(status.isOpen ? Palette.lime : Palette.cyan)
        .sheet(isPresented: $showingHours) { CafeHoursSheet() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Steve's Café, \(status.headline), \(status.detail). Based on regular hours; holidays may differ.")
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
    let goBack: () -> Void

    @State private var name = ""
    @State private var selectedPlan: MealPlanType?
    @State private var errorMessage = ""
    @State private var showingClearConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button(action: goBack) {
                        Label("BACK", systemImage: "arrow.left")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    BrandHeader()
                }
                .padding(.bottom, 24)
                .overlay(alignment: .bottom) { Palette.cyan.frame(height: 2) }

                Text("Settings")
                    .font(.system(size: 39, weight: .black, design: .rounded))
                    .tracking(-2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.top, 24)

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

                Button("CLEAR PLAN FROM THIS IPHONE", role: .destructive) {
                    showingClearConfirmation = true
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .underline()
                .foregroundStyle(Palette.paper)
                .padding(.top, 48)
            }
            .padding(.horizontal, 24)
            .padding(.top, 17)
            .padding(.bottom, 35)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear(perform: loadFields)
        .confirmationDialog("Clear your meal plan?", isPresented: $showingClearConfirmation) {
            Button("Clear plan", role: .destructive) {
                store.clear()
            }
        } message: {
            Text("Your saved count and meal record will be removed from this iPhone.")
        }
    }

    private func loadFields() {
        guard let plan = store.plan else { return }
        name = plan.name
        selectedPlan = plan.planType
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
        store.updateSettings(name: trimmed, planType: selectedPlan)
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
