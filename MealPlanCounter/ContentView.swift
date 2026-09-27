import SwiftUI

private enum Palette {
    static let indigo = Color(red: 13 / 255, green: 7 / 255, blue: 140 / 255)
    static let paper = Color(red: 215 / 255, green: 255 / 255, blue: 254 / 255)
    static let cyan = Color(red: 0, green: 1, blue: 1)
    static let lime = Color(red: 0, green: 1, blue: 0)
    static let muted = Color(red: 157 / 255, green: 253 / 255, blue: 255 / 255)
}

private enum Screen {
    case count
    case account
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
                        if screen == .count {
                            CounterView(plan: plan, useMeal: store.useMeal, undoMeal: store.undoLastMeal) {
                                screen = .account
                            }
                        } else {
                            AccountView(store: store) { screen = .count }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    bottomBar
                }
            } else {
                SetupView { name, total in
                    store.create(name: name, totalMeals: total)
                    screen = .count
                }
            }
        }
        .foregroundStyle(Palette.paper)
        .tint(Palette.cyan)
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            tabButton("COUNT", symbol: "circle.grid.2x2.fill", destination: .count)
            tabButton("ACCOUNT", symbol: "person.crop.circle", destination: .account)
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
    let create: (String, Int) -> Void

    @State private var name = "Lily"
    @State private var totalText = "150"
    @State private var showError = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, total }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    BrandHeader()
                    Spacer(minLength: 86)

                    Eyebrow("MEAL PLAN COUNTER")
                    Text("Know your\nnext bite.")
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

                    LabeledInput(label: "YOUR NAME", text: $name, placeholder: "Lily")
                        .focused($focusedField, equals: .name)
                        .textContentType(.givenName)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .total }

                    LabeledInput(label: "MEALS IN YOUR PLAN", text: $totalText, placeholder: "150")
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .total)
                        .padding(.top, 20)

                    if showError {
                        Text("Enter a name and a meal total greater than zero.")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Palette.lime)
                            .padding(.top, 12)
                    }

                    ActionButton(title: "Start counting", symbol: "arrow.right") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, let total = Int(totalText), total > 0 else {
                            showError = true
                            return
                        }
                        focusedField = nil
                        create(trimmed, total)
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
    let openAccount: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    BrandHeader()
                    Spacer()
                    Button(action: openAccount) {
                        Text(String(plan.name.prefix(1)).uppercased())
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .frame(width: 42, height: 42)
                            .overlay(Circle().stroke(Palette.cyan, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open account")
                }

                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    CafeStatusCard(status: CafeHours.status(at: timeline.date))
                }
                .padding(.top, 43)

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
                        Eyebrow("STARTED WITH: \(plan.totalMeals) MEALS")
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

private struct AccountView: View {
    @ObservedObject var store: MealPlanStore
    let goBack: () -> Void

    @State private var name = ""
    @State private var totalText = ""
    @State private var usedText = ""
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

                Text("Your plan.")
                    .font(.system(size: 47, weight: .black, design: .rounded))
                    .tracking(-3)
                    .padding(.top, 37)

                Text("Edit your starting total or correct the number used. Changes stay on this iPhone.")
                    .font(.system(size: 15, weight: .medium))
                    .lineSpacing(4)
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 13)
                    .padding(.bottom, 33)

                LabeledInput(label: "YOUR NAME", text: $name, placeholder: "Lily")
                    .textContentType(.givenName)
                LabeledInput(label: "TOTAL MEALS IN PLAN", text: $totalText, placeholder: "150")
                    .keyboardType(.numberPad)
                    .padding(.top, 22)
                LabeledInput(label: "MEALS USED", text: $usedText, placeholder: "0")
                    .keyboardType(.numberPad)
                    .padding(.top, 22)

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.lime)
                        .padding(.top, 14)
                }

                ActionButton(title: "Save changes", symbol: "checkmark") {
                    save()
                }
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
            Text("Your saved count will be removed from this iPhone.")
        }
    }

    private func loadFields() {
        guard let plan = store.plan else { return }
        name = plan.name
        totalText = String(plan.totalMeals)
        usedText = String(plan.usedMeals)
        errorMessage = ""
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let total = Int(totalText), total > 0,
              let used = Int(usedText), used >= 0, used <= total else {
            errorMessage = "Enter a name, a total above zero, and used meals between zero and the total."
            return
        }
        store.update(name: trimmed, totalMeals: total, usedMeals: used)
        goBack()
    }
}

private struct BrandHeader: View {
    var body: some View {
        Image("CalArtsLogo")
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .frame(width: 144, height: 24, alignment: .leading)
            .foregroundStyle(Palette.paper)
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
