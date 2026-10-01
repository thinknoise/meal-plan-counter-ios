import Combine
import CoreLocation
import Foundation
import UserNotifications

@MainActor
final class CafeReminder: NSObject, ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var statusMessage = "Off. Turn this on for a reminder when you arrive at Steve's Café."
    @Published private(set) var needsSystemSettings = false

    private static let preferenceKey = "steves-cafe-reminder-enabled-v1"
    private static let requestID = "steves-cafe-entry-30m"
    private let defaults: UserDefaults
    private let locationManager = CLLocationManager()
    private let notifications = UNUserNotificationCenter.current()
    private var revision = 0
    private var isRegistering = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.preferenceKey)
        super.init()
        locationManager.delegate = self
        notifications.delegate = self
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
        defaults.removeObject(forKey: Self.preferenceKey)
    }

    // A pending location notification survives app launches. Refresh only checks
    // authorization and restores the request if the system has removed it.
    func refresh() {
        let currentRevision = revision
        Task { await synchronize(revision: currentRevision) }
    }

    private func requestPermissionsAndRefresh(revision expectedRevision: Int) async {
        let notificationSettings = await notifications.notificationSettings()
        guard isCurrent(expectedRevision) else { return }

        if notificationSettings.authorizationStatus == .notDetermined {
            _ = try? await notifications.requestAuthorization(options: [.alert])
        }
        guard isCurrent(expectedRevision) else { return }

        let updatedSettings = await notifications.notificationSettings()
        guard isCurrent(expectedRevision) else { return }
        guard updatedSettings.authorizationStatus == .authorized,
              updatedSettings.alertSetting == .enabled else {
            await synchronize(revision: expectedRevision)
            return
        }

        guard CLLocationManager.locationServicesEnabled() else {
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

        guard CLLocationManager.locationServicesEnabled() else {
            pause("Location Services are off. Turn them on in iPhone Settings to use this reminder.", openSettings: true)
            return
        }
        switch locationManager.authorizationStatus {
        case .notDetermined:
            pause("Turn this reminder off and on to allow location access.")
            return
        case .denied, .restricted:
            pause("Location access is off for CAMPc. Allow While Using the App in iPhone Settings to use this reminder.", openSettings: true)
            return
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            pause("Location permission is unavailable. Check iPhone Settings.", openSettings: true)
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
