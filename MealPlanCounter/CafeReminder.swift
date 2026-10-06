import Combine
import CoreLocation
import Foundation
import UserNotifications

private enum TimedReminderKind: CaseIterable {
    case opening
    case closing

    var requestPrefix: String {
        switch self {
        case .opening: "steves-cafe-opening-"
        case .closing: "steves-cafe-closing-"
        }
    }

    var signatureKey: String {
        switch self {
        case .opening: "steves-cafe-opening-schedule-v1"
        case .closing: "steves-cafe-closing-schedule-v1"
        }
    }
}

@MainActor
final class CafeReminder: NSObject, ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var statusMessage = "Off. Turn this on for a reminder when you arrive at Steve's Café."
    @Published private(set) var needsSystemSettings = false
    @Published private(set) var isMealTimeEnabled: Bool
    @Published private(set) var mealTimeStatusMessage = "Off."
    @Published private(set) var mealTimeNeedsSystemSettings = false
    @Published private(set) var isClosingSoonEnabled: Bool
    @Published private(set) var closingSoonStatusMessage = "Off."
    @Published private(set) var closingSoonNeedsSystemSettings = false

    var needsAnySystemSettings: Bool {
        needsSystemSettings || mealTimeNeedsSystemSettings || closingSoonNeedsSystemSettings
    }

    private static let preferenceKey = "steves-cafe-reminder-enabled-v1"
    private static let mealTimePreferenceKey = "steves-cafe-meal-time-enabled-v1"
    private static let closingSoonPreferenceKey = "steves-cafe-closing-soon-enabled-v1"
    private static let requestID = "steves-cafe-entry-30m"
    private let defaults: UserDefaults
    private let locationManager = CLLocationManager()
    private let notifications = UNUserNotificationCenter.current()
    private var revision = 0
    private var isRegistering = false
    private var mealTimeRevision = 0
    private var closingSoonRevision = 0
    private var isRegisteringMealTime = false
    private var isRegisteringClosingSoon = false
    private var notificationPermissionTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.preferenceKey)
        isMealTimeEnabled = defaults.bool(forKey: Self.mealTimePreferenceKey)
        isClosingSoonEnabled = defaults.bool(forKey: Self.closingSoonPreferenceKey)
        super.init()
        locationManager.delegate = self
        notifications.delegate = self
        for kind in TimedReminderKind.allCases where !timedEnabled(kind) {
            cancelTimedRequests(kind)
        }
    }

    func enable() {
        guard !isEnabled else { return }
        isEnabled = true
        statusMessage = "Setting up the reminder…"
        needsSystemSettings = false
        defaults.set(true, forKey: Self.preferenceKey)
        revision += 1
        let currentRevision = revision
        Task { await requestPermissionsAndRefresh(revision: currentRevision) }
    }

    func disable() {
        revision += 1
        isEnabled = false
        defaults.set(false, forKey: Self.preferenceKey)
        statusMessage = "Off. Turn this on for a reminder when you arrive at Steve's Café."
        needsSystemSettings = false
        notifications.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
        notifications.removeDeliveredNotifications(withIdentifiers: [Self.requestID])
    }

    func clear() {
        disable()
        setMealTimeEnabled(false)
        setClosingSoonEnabled(false)
        defaults.removeObject(forKey: Self.preferenceKey)
        defaults.removeObject(forKey: Self.mealTimePreferenceKey)
        defaults.removeObject(forKey: Self.closingSoonPreferenceKey)
    }

    func setMealTimeEnabled(_ enabled: Bool) {
        setTimedEnabled(enabled, for: .opening)
    }

    func setClosingSoonEnabled(_ enabled: Bool) {
        setTimedEnabled(enabled, for: .closing)
    }

    // A pending location notification survives app launches. Refresh only checks
    // authorization and restores the request if the system has removed it.
    func refresh() {
        let currentRevision = revision
        Task { await synchronize(revision: currentRevision) }
        for kind in TimedReminderKind.allCases where timedEnabled(kind) {
            refreshTimed(kind)
        }
    }

    private func requestPermissionsAndRefresh(revision expectedRevision: Int) async {
        await requestNotificationPermissionIfNeeded()
        guard isCurrent(expectedRevision) else { return }

        let updatedSettings = await notifications.notificationSettings()
        guard isCurrent(expectedRevision) else { return }
        guard updatedSettings.authorizationStatus == .authorized,
              updatedSettings.alertSetting == .enabled else {
            await synchronize(revision: expectedRevision)
            return
        }

        if locationManager.authorizationStatus == .notDetermined {
            statusMessage = "Waiting for location permission."
            locationManager.requestWhenInUseAuthorization()
        } else {
            await synchronize(revision: expectedRevision)
        }
    }

    private func synchronize(revision expectedRevision: Int) async {
        guard isCurrent(expectedRevision) else { return }
        let settings = await notifications.notificationSettings()
        guard isCurrent(expectedRevision) else { return }

        switch settings.authorizationStatus {
        case .denied:
            pause("Notifications are off for CAMPc. Allow alerts in iPhone Settings to use this reminder.", openSettings: true)
            return
        case .notDetermined:
            pause("Turn this reminder off and on to allow notifications.")
            return
        case .provisional:
            pause("Turn on notification alerts for CAMPc in iPhone Settings to see this reminder.", openSettings: true)
            return
        case .authorized, .ephemeral:
            if settings.alertSetting != .enabled {
                pause("Turn on notification alerts for CAMPc in iPhone Settings to see this reminder.", openSettings: true)
                return
            }
        @unknown default:
            pause("Notification permission is unavailable. Check iPhone Settings.", openSettings: true)
            return
        }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            pause("Turn this reminder off and on to allow location access.")
            return
        case .denied:
            pause("Location Services or CAMPc location access is off. Check iPhone Settings to use this reminder.", openSettings: true)
            return
        case .restricted:
            pause("Location access is restricted. Check iPhone Settings to use this reminder.", openSettings: true)
            return
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            pause("Location permission is unavailable. Check iPhone Settings.", openSettings: true)
            return
        }

        guard locationManager.accuracyAuthorization == .fullAccuracy else {
            pause("Precise Location is off. Turn it on for CAMPc in iPhone Settings to use this 30-meter reminder.", openSettings: true)
            return
        }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            pause("Location reminders are unavailable on this device.")
            return
        }
        guard !isRegistering else { return }
        isRegistering = true
        defer {
            isRegistering = false
            if revision != expectedRevision && isEnabled { refresh() }
        }

        let pending = await notifications.pendingNotificationRequests()
        guard isCurrent(expectedRevision) else { return }
        if !pending.contains(where: { $0.identifier == Self.requestID }) {
            do {
                try await notifications.add(Self.notificationRequest())
            } catch {
                guard isCurrent(expectedRevision) else { return }
                statusMessage = "Couldn't set up the reminder. Turn it off and on to try again."
                needsSystemSettings = false
                return
            }
        }
        guard isCurrent(expectedRevision) else {
            notifications.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
            return
        }
        statusMessage = "Ready. The reminder appears when you enter Steve's Café. Leave and re-enter to test it."
        needsSystemSettings = false
    }

    private func pause(_ message: String, openSettings: Bool = false) {
        notifications.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
        statusMessage = message
        needsSystemSettings = openSettings
    }

    private func isCurrent(_ expectedRevision: Int) -> Bool {
        isEnabled && revision == expectedRevision
    }

    private func requestNotificationPermissionIfNeeded() async {
        if let notificationPermissionTask {
            await notificationPermissionTask.value
            return
        }
        let task = Task {
            let settings = await notifications.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await notifications.requestAuthorization(options: [.alert])
            }
        }
        notificationPermissionTask = task
        await task.value
        notificationPermissionTask = nil
    }

    private func setTimedEnabled(_ enabled: Bool, for kind: TimedReminderKind) {
        switch kind {
        case .opening:
            mealTimeRevision += 1
            isMealTimeEnabled = enabled
            defaults.set(enabled, forKey: Self.mealTimePreferenceKey)
        case .closing:
            closingSoonRevision += 1
            isClosingSoonEnabled = enabled
            defaults.set(enabled, forKey: Self.closingSoonPreferenceKey)
        }

        if enabled {
            setTimedStatus("Setting up the reminder…", for: kind)
            let expectedRevision = timedRevision(kind)
            Task {
                await requestNotificationPermissionIfNeeded()
                await synchronizeTimed(kind, revision: expectedRevision)
            }
        } else {
            cancelTimedRequests(kind)
            defaults.removeObject(forKey: kind.signatureKey)
            setTimedStatus("Off.", for: kind)
        }
    }

    private func refreshTimed(_ kind: TimedReminderKind) {
        let expectedRevision = timedRevision(kind)
        Task { await synchronizeTimed(kind, revision: expectedRevision) }
    }

    private func synchronizeTimed(_ kind: TimedReminderKind, revision expectedRevision: Int) async {
        guard isTimedCurrent(kind, revision: expectedRevision) else { return }
        let settings = await notifications.notificationSettings()
        guard isTimedCurrent(kind, revision: expectedRevision) else { return }

        switch settings.authorizationStatus {
        case .denied:
            pauseTimed(kind, message: "Notifications are off for CAMPc. Allow alerts in iPhone Settings.", openSettings: true)
            return
        case .notDetermined:
            pauseTimed(kind, message: "Turn this reminder off and on to allow notifications.")
            return
        case .provisional:
            pauseTimed(kind, message: "Turn on notification alerts for CAMPc in iPhone Settings.", openSettings: true)
            return
        case .authorized, .ephemeral:
            if settings.alertSetting != .enabled {
                pauseTimed(kind, message: "Turn on notification alerts for CAMPc in iPhone Settings.", openSettings: true)
                return
            }
        @unknown default:
            pauseTimed(kind, message: "Notification permission is unavailable. Check iPhone Settings.", openSettings: true)
            return
        }

        guard !timedIsRegistering(kind) else { return }
        setTimedRegistering(true, for: kind)
        defer {
            setTimedRegistering(false, for: kind)
            if timedRevision(kind) != expectedRevision && timedEnabled(kind) { refreshTimed(kind) }
        }

        let expected = Self.timedRequests(for: kind)
        let signature = Self.scheduleSignature(for: expected)
        let pending = await notifications.pendingNotificationRequests()
        guard isTimedCurrent(kind, revision: expectedRevision) else { return }
        let current = pending.filter { $0.identifier.hasPrefix(kind.requestPrefix) }
        let expectedIDs = Set(expected.map(\.identifier))
        if defaults.string(forKey: kind.signatureKey) == signature,
           Set(current.map(\.identifier)) == expectedIDs {
            setTimedStatus(readyMessage(for: kind), for: kind)
            return
        }

        let obsoleteIDs = current.map(\.identifier).filter { !expectedIDs.contains($0) }
        if !obsoleteIDs.isEmpty {
            notifications.removePendingNotificationRequests(withIdentifiers: obsoleteIDs)
        }
        for request in expected {
            guard isTimedCurrent(kind, revision: expectedRevision) else {
                cancelTimedRequests(kind)
                return
            }
            do {
                // The stable identifier replaces an older request when hours change.
                try await notifications.add(request)
            } catch {
                guard isTimedCurrent(kind, revision: expectedRevision) else { return }
                cancelTimedRequests(kind)
                defaults.removeObject(forKey: kind.signatureKey)
                setTimedStatus("Couldn't schedule reminders. Turn this off and on to try again.", for: kind)
                return
            }
        }
        guard isTimedCurrent(kind, revision: expectedRevision) else {
            cancelTimedRequests(kind)
            return
        }
        defaults.set(signature, forKey: kind.signatureKey)
        setTimedStatus(readyMessage(for: kind), for: kind)
    }

    private func pauseTimed(_ kind: TimedReminderKind, message: String, openSettings: Bool = false) {
        cancelTimedRequests(kind)
        defaults.removeObject(forKey: kind.signatureKey)
        setTimedStatus(message, for: kind, openSettings: openSettings)
    }

    private func cancelTimedRequests(_ kind: TimedReminderKind) {
        let identifiers = Self.allTimedIDs(for: kind)
        notifications.removePendingNotificationRequests(withIdentifiers: identifiers)
        notifications.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func setTimedStatus(_ message: String, for kind: TimedReminderKind, openSettings: Bool = false) {
        switch kind {
        case .opening:
            mealTimeStatusMessage = message
            mealTimeNeedsSystemSettings = openSettings
        case .closing:
            closingSoonStatusMessage = message
            closingSoonNeedsSystemSettings = openSettings
        }
    }

    private func readyMessage(for kind: TimedReminderKind) -> String {
        switch kind {
        case .opening: "Ready. Follows Steve's regular meal opening times."
        case .closing: "Ready. Alerts 20 minutes before each regular meal period ends."
        }
    }

    private func timedEnabled(_ kind: TimedReminderKind) -> Bool {
        switch kind {
        case .opening: isMealTimeEnabled
        case .closing: isClosingSoonEnabled
        }
    }

    private func timedRevision(_ kind: TimedReminderKind) -> Int {
        switch kind {
        case .opening: mealTimeRevision
        case .closing: closingSoonRevision
        }
    }

    private func isTimedCurrent(_ kind: TimedReminderKind, revision expectedRevision: Int) -> Bool {
        timedEnabled(kind) && timedRevision(kind) == expectedRevision
    }

    private func timedIsRegistering(_ kind: TimedReminderKind) -> Bool {
        switch kind {
        case .opening: isRegisteringMealTime
        case .closing: isRegisteringClosingSoon
        }
    }

    private func setTimedRegistering(_ registering: Bool, for kind: TimedReminderKind) {
        switch kind {
        case .opening: isRegisteringMealTime = registering
        case .closing: isRegisteringClosingSoon = registering
        }
    }

    private static func allTimedIDs(for kind: TimedReminderKind) -> [String] {
        (1...7).flatMap { weekday in
            MealType.allCases.map { mealType in
                "\(kind.requestPrefix)\(weekday)-\(mealType.rawValue.lowercased())"
            }
        }
    }

    private static func timedRequests(for kind: TimedReminderKind) -> [UNNotificationRequest] {
        let timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        return (1...7).flatMap { weekday in
            CafeHours.mealServices(for: weekday).map { period in
                let minute = kind == .opening ? period.service.startMinute : period.service.endMinute - 20
                var components = DateComponents()
                components.calendar = calendar
                components.timeZone = timeZone
                components.weekday = weekday
                components.hour = minute / 60
                components.minute = minute % 60

                let name = period.mealType.rawValue
                let content = UNMutableNotificationContent()
                // Keep these as quiet alerts: no sound, badge, or elevated interruption level.
                if kind == .opening {
                    content.title = "\(name) is open"
                    content.body = "Steve's Café is serving \(name.lowercased())."
                } else {
                    content.title = "\(name) ends in 20 minutes"
                    content.body = "Steve's Café is closing for \(name.lowercased()) soon."
                }
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let identifier = "\(kind.requestPrefix)\(weekday)-\(name.lowercased())"
                return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            }
        }
    }

    private static func scheduleSignature(for requests: [UNNotificationRequest]) -> String {
        requests.map { request in
            let components = (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents
            return "\(request.identifier)|\(components?.timeZone?.identifier ?? "")|\(components?.weekday ?? -1)|\(components?.hour ?? -1)|\(components?.minute ?? -1)|\(request.content.title)|\(request.content.body)"
        }.joined(separator: "\n")
    }

    private static func notificationRequest() -> UNNotificationRequest {
        let center = CLLocationCoordinate2D(latitude: 34.393155226447824,
                                              longitude: -118.56626246555751)
        let region = CLCircularRegion(center: center, radius: 30, identifier: requestID)
        region.notifyOnEntry = true
        region.notifyOnExit = false

        let content = UNMutableNotificationContent()
        content.title = "You @ Steve's Cafe?"
        content.body = "Don't forgets to count yo'meal"

        let trigger = UNLocationNotificationTrigger(region: region, repeats: true)
        return UNNotificationRequest(identifier: requestID, content: content, trigger: trigger)
    }
}

extension CafeReminder: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.refresh() }
    }
}

extension CafeReminder: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
