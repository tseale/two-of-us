import CoreLocation
import Foundation
import SwiftData
import UserNotifications

/// Watches the daycare's geofence and turns an arrival into the right
/// one-tap prompt: "Drop off Miller?" in the morning, "Pick up Miller?" while
/// he's there. Monitoring runs on `CLMonitor` (iOS relaunches the app for
/// events, so the prompts work with the app closed); the decision of WHAT to
/// ask is `DaycareGeofencePlanner`'s, off the same store state Home reads.
///
/// Config (location, radius, on/off) is shared via `SharedSettings`; the
/// Always location permission is per-device — each parent grants their own.
@MainActor
@Observable
final class DaycareGeofenceManager: NSObject {
    static let shared = DaycareGeofenceManager()

    private static let conditionIdentifier = "daycare"
    private static let lastPromptKey = "daycare.geofence.lastPrompt"

    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Whether this phone is inside the daycare fence right now — Home reads
    /// it to auto-expand the pick-up control on arrival. Follows the same
    /// `CLMonitor` events the prompts do, seeded from the condition's last
    /// recorded state on each refresh; false whenever the fence is down
    /// (disabled, no pin, no Always permission), so it can never hold a stale
    /// "near" across a teardown.
    private(set) var isNearDaycare = false

    private let location = CLLocationManager()
    private var monitorTask: Task<CLMonitor, Never>?
    private var eventsTask: Task<Void, Never>?
    /// One-shot "use current location" continuation for the settings page.
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    private override init() {
        super.init()
        location.delegate = self
        authorizationStatus = location.authorizationStatus
    }

    /// Whether this device can actually monitor in the background. When-in-use
    /// keeps the settings map working; the fence needs Always.
    var hasAlwaysPermission: Bool { authorizationStatus == .authorizedAlways }

    /// Steps the system prompts: nothing → When In Use → Always. Call from the
    /// settings page when the arrival-reminders toggle goes on.
    func requestPermission() {
        switch authorizationStatus {
        case .notDetermined:
            location.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            location.requestAlwaysAuthorization()
        default:
            break
        }
    }

    /// (Re)builds the fence off the current shared settings. Call at launch
    /// (a geofence event may be why we launched), on foreground (the
    /// co-parent's edits arrive via sync), and after local daycare edits.
    func refreshMonitoring() {
        Task { await applyMonitoringState() }
    }

    private func applyMonitoringState() async {
        let settings = canonicalSettings()
        let coordinate = settings?.daycareCoordinate
        let monitor = await ensureMonitor()

        guard let settings, let coordinate,
              settings.daycareGeofenceEnabled,
              hasAlwaysPermission,
              !LocalPrefs.shared.demoModeEnabled else {
            // Tear the condition down so a disabled fence can't relaunch us.
            await monitor.remove(Self.conditionIdentifier)
            isNearDaycare = false
            return
        }

        let condition = CLMonitor.CircularGeographicCondition(
            center: CLLocationCoordinate2D(latitude: coordinate.latitude,
                                           longitude: coordinate.longitude),
            radius: max(100, settings.daycareGeofenceRadiusMeters))
        // Assume we start outside: the first prompt should come from an
        // arrival, not from flipping the toggle on while standing at home.
        await monitor.add(condition, identifier: Self.conditionIdentifier,
                          assuming: .unsatisfied)
        isNearDaycare = await monitor.record(for: Self.conditionIdentifier)?
            .lastEvent.state == .satisfied
    }

    /// The one `CLMonitor` (one instance per name is the API contract),
    /// created lazily; its events loop runs for the app's lifetime. The
    /// creation is memoized as a Task so two refreshes interleaving across
    /// the init's suspension point can't mint two instances.
    private func ensureMonitor() async -> CLMonitor {
        if let monitorTask { return await monitorTask.value }
        let task = Task { await CLMonitor("DaycareMonitor") }
        monitorTask = task
        let monitor = await task.value
        guard eventsTask == nil else { return monitor }
        eventsTask = Task { [weak self] in
            do {
                for try await event in await monitor.events {
                    guard event.identifier == Self.conditionIdentifier else { continue }
                    await self?.setNearDaycare(event.state == .satisfied)
                    await self?.publishPresence(near: event.state == .satisfied,
                                                at: event.date)
                    guard event.state == .satisfied else { continue }
                    await self?.handleArrival(at: event.date)
                }
            } catch {
                AppLog.daycare.error("Geofence monitor failed: \(error, privacy: .public)")
            }
        }
        return monitor
    }

    /// One-shot fix for the settings page's "Use current location" button.
    func currentLocation() async -> CLLocationCoordinate2D? {
        guard authorizationStatus == .authorizedWhenInUse
                || authorizationStatus == .authorizedAlways else { return nil }
        return await withCheckedContinuation { continuation in
            // A second tap while a fix is pending resolves the first as nil.
            locationContinuation?.resume(returning: nil)
            locationContinuation = continuation
            location.requestLocation()
        }
    }

    private func setNearDaycare(_ near: Bool) {
        isNearDaycare = near
    }

    /// Shares the crossing on the settings record, so the co-parent's phone
    /// can say "someone's at daycare" — and knows never to show its own
    /// slider. Crossings only (the monitor delivers transitions, not ticks),
    /// and `publishDaycarePresence` drops a no-change rewrite.
    private func publishPresence(near: Bool, at when: Date) {
        guard !LocalPrefs.shared.demoModeEnabled,
              canonicalSettings()?.daycareGeofenceEnabled == true else { return }
        EventStore(context: AppModelContainer.shared.mainContext).publishDaycarePresence(
            DaycarePresence(deviceID: LocalPrefs.shared.deviceID,
                            timestamp: when,
                            type: near ? .arrival : .departure))
    }

    // MARK: Arrival → prompt

    private func handleArrival(at when: Date) async {
        guard !LocalPrefs.shared.demoModeEnabled,
              let settings = canonicalSettings(),
              settings.daycareGeofenceEnabled else { return }
        let context = AppModelContainer.shared.mainContext
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: when)

        let checks = ((try? context.fetch(FetchDescriptor<CheckEvent>(
            predicate: #Predicate { $0.deletedAt == nil }))) ?? [])
            .filter { $0.timestamp >= dayStart }
        let attending = DaycareStatus.attendance(
            checks: checks.map { ($0.timestamp, $0.type) },
            firstDaycareEvent: firstDaycareEventToday(dayStart: dayStart, in: context),
            dayStart: dayStart, now: when,
            closeMinute: settings.daycareCloseMinute) != nil

        guard let prompt = DaycareGeofencePlanner.prompt(
            now: when, dayStart: dayStart,
            openMinute: settings.daycareOpenMinute,
            closeMinute: settings.daycareCloseMinute,
            isOperatingDay: settings.isDaycareDay(when, calendar: calendar),
            attending: attending,
            checkedOutToday: checks.contains { $0.type == .checkOut && $0.timestamp <= when },
            homeToday: checks.contains { $0.type == .notAttending && $0.timestamp <= when }
        ) else { return }

        // One ask per prompt per day — lingering at the edge of the fence
        // (satisfied → unsatisfied → satisfied) must not nag.
        let dedupeKey = "\(prompt.rawValue).\(dayKey(dayStart))"
        guard UserDefaults.standard.string(forKey: Self.lastPromptKey) != dedupeKey else { return }
        UserDefaults.standard.set(dedupeKey, forKey: Self.lastPromptKey)

        await post(prompt, at: when, settings: settings, in: context)
    }

    private func post(_ prompt: DaycareGeofencePlanner.Prompt, at when: Date,
                      settings: SharedSettings, in context: ModelContext) async {
        guard await NotificationManager.requestAuthorization() else { return }
        let babyName = (try? context.fetch(FetchDescriptor<Baby>()))?.first
            .flatMap { $0.name.isEmpty ? nil : $0.name } ?? "the baby"
        let place = settings.daycareDisplayName

        let content = UNMutableNotificationContent()
        content.interruptionLevel = .timeSensitive
        switch prompt {
        case .dropOff:
            // Deliberately plain — one line, one action. The whiteboard
            // answers live on Home's slide-to-drop-off card, not here.
            content.title = "Drop off \(babyName)?"
            content.body = "You're at \(place) — log the drop-off with one tap."
            content.categoryIdentifier = NotificationID.Category.geofenceDropOff
        case .pickUp:
            content.title = "Pick up \(babyName)?"
            content.body = "You're at \(place) — log the pick-up with one tap."
            content.categoryIdentifier = NotificationID.Category.geofencePickUp
        }
        content.threadIdentifier = NotificationID.Thread.daycare(day: dayKey(.now))

        let request = UNNotificationRequest(
            identifier: NotificationID.Request.geofence(prompt.rawValue),
            content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
        AppLog.daycare.log("Posted geofence \(prompt.rawValue, privacy: .public) prompt")
    }

    /// The earliest daycare-sourced event of the day among the kinds staff log
    /// constantly — the check-in stand-in on marker-less Brightwheel days, so
    /// an afternoon arrival asks "pick up", not "drop off". (HomeView sweeps
    /// all twelve kinds; feeds/sleeps/diapers/notes are plenty for a prompt.)
    private func firstDaycareEventToday(dayStart: Date, in context: ModelContext) -> Date? {
        let source = EventSource.brightwheel.rawValue
        func earliest<T: PersistentModel>(_ type: T.Type, _ time: (T) -> Date,
                                          _ sourceRaw: (T) -> String?) -> Date? {
            ((try? context.fetch(FetchDescriptor<T>())) ?? [])
                .filter { sourceRaw($0) == source && time($0) >= dayStart }
                .map(time).min()
        }
        return [
            earliest(FeedEvent.self, { $0.timestamp }, { $0.sourceRaw }),
            earliest(SleepEvent.self, { $0.startedAt }, { $0.sourceRaw }),
            earliest(DiaperEvent.self, { $0.timestamp }, { $0.sourceRaw }),
            earliest(NoteEvent.self, { $0.timestamp }, { $0.sourceRaw }),
        ].compactMap { $0 }.min()
    }

    private func canonicalSettings() -> SharedSettings? {
        SharedSettings.canonical(
            (try? AppModelContainer.shared.mainContext.fetch(FetchDescriptor<SharedSettings>())) ?? [])
    }

    private func dayKey(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }
}

extension DaycareGeofenceManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            // A fresh Always grant arms the fence without revisiting Settings.
            self.refreshMonitoring()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in
            self.locationContinuation?.resume(returning: coordinate)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in
            self.locationContinuation?.resume(returning: nil)
            self.locationContinuation = nil
        }
    }
}
