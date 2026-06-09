import Foundation
import SwiftData

/// Sample-data world for **Demo mode** (see `LocalPrefs.demoModeEnabled`).
///
/// `seed(into:)` fills a throwaway in-memory `ModelContext` with a baby, a
/// co-parent, two guests, and ~3 weeks of feeds/sleeps/diapers so the whole app
/// can be shown off on a real device. Models are inserted directly (never through
/// `EventStore`) so seeding fires no widgets / Live Activities / sync.
///
/// `DemoSession` overrides this device's sharing identity while demo mode is on so
/// the owner's People-management controls render, then restores the real values on
/// exit. The real store is never touched.
enum DemoData {
    /// Fixed identity for the demo "you" so the seed and the `DemoSession` override
    /// agree (the owner's row shows "(you)" and others get role controls).
    static let ownerID = UUID(uuidString: "DE110000-0000-0000-0000-00000000000A")!

    static func seed(into context: ModelContext) {
        // In-memory store is always fresh, but stay idempotent just in case.
        guard (try? context.fetch(FetchDescriptor<Baby>()))?.isEmpty != false else { return }

        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)

        let baby = Baby(
            name: "Miller",
            dateOfBirth: cal.date(byAdding: .weekOfYear, value: -14, to: now) ?? now
        )
        context.insert(baby)

        // Owner first (so even a no-override fetch resolves "you"), then co-parent,
        // then two guests. Colors come from the shared palette.
        let you = Participant(id: ownerID, displayName: "Taylor",
                              colorHex: ParticipantColors.palette[0], role: .full)
        let partner = Participant(displayName: "Jordan",
                                  colorHex: ParticipantColors.palette[3], role: .full)
        let grandma = Participant(displayName: "Grandma",
                                  colorHex: ParticipantColors.palette[2], role: .logger)
        let nanny = Participant(displayName: "Nanny",
                                colorHex: ParticipantColors.palette[4], role: .logger)
        [you, partner, grandma, nanny].forEach { context.insert($0) }

        context.insert(SharedSettings())

        // MARK: Event helpers (stamp denormalized logger identity from the participant)

        func feed(_ oz: Double, _ date: Date, by p: Participant, note: String? = nil) {
            guard date <= now else { return }
            context.insert(FeedEvent(
                baby: baby, amountOz: oz, timestamp: date, notes: note,
                loggedByID: p.id, loggedByName: p.displayName, loggedByColorHex: p.colorHex
            ))
        }
        func sleep(_ start: Date, hours: Double, by p: Participant, note: String? = nil) {
            guard start <= now else { return }
            context.insert(SleepEvent(
                baby: baby, startedAt: start,
                endedAt: min(now, start.addingTimeInterval(hours * 3600)), notes: note,
                loggedByID: p.id, loggedByName: p.displayName, loggedByColorHex: p.colorHex
            ))
        }
        func diaper(_ type: DiaperType, _ date: Date, by p: Participant) {
            guard date <= now else { return }
            context.insert(DiaperEvent(
                baby: baby, type: type, timestamp: date,
                loggedByID: p.id, loggedByName: p.displayName, loggedByColorHex: p.colorHex
            ))
        }

        let days = 21
        for d in 0..<days {
            guard let dayStart = cal.date(byAdding: .day, value: -d, to: today) else { continue }
            // Jitter so timestamps don't all land on the hour.
            func at(_ hour: Double) -> Date {
                dayStart.addingTimeInterval(hour * 3600 + Double((d * 7 + Int(hour)) % 25) * 60)
            }

            // Feeds: night feed (~2:30am) by the partner; daytime ~every 3h split
            // between you and, midday on some days, a guest.
            feed(3, at(2.5), by: partner, note: d % 4 == 0 ? "Sleepy feed, took a while" : nil)
            for h in stride(from: 6, through: 21, by: 3) {
                let oz = 2.5 + Double((h / 3) % 3) * 0.5
                let who: Participant
                if h == 12 && d % 3 == 0 { who = grandma }
                else if h == 15 && d % 4 == 1 { who = nanny }
                else if h >= 18 { who = partner }
                else { who = you }
                feed(oz, at(Double(h)), by: who,
                     note: (h == 9 && d % 5 == 0) ? "Spit up a little after" : nil)
            }

            // Sleep: a growing overnight stretch (logged the next morning) plus a
            // midday nap. Day 0's overnight is left to the in-progress sleep below.
            if d > 0 {
                let stretch = 4.0 + Double(days - 1 - d) * 0.18   // matures toward recent days
                sleep(at(22), hours: stretch, by: partner,
                      note: d % 6 == 0 ? "Down without a fuss" : nil)
            }
            sleep(at(13), hours: 1.4 + Double(d % 3) * 0.2, by: you)
            if d % 2 == 0 { sleep(at(9.5), hours: 0.75, by: grandma) }   // short morning nap

            // Diapers ~every 3h, cycling wet → wet → dirty → both, across caregivers.
            let changers = [you, partner, grandma, nanny]
            for (i, h) in stride(from: 6, through: 22, by: 3).enumerated() {
                let type: DiaperType = (i % 4 == 2) ? .dirty : (i % 4 == 3 ? .both : .wet)
                diaper(type, at(Double(h)), by: changers[(d + i) % changers.count])
            }
        }

        // One in-progress sleep so Home shows the active-sleep card / running timer.
        context.insert(SleepEvent(
            baby: baby, startedAt: now.addingTimeInterval(-40 * 60), endedAt: nil,
            loggedByID: you.id, loggedByName: you.displayName, loggedByColorHex: you.colorHex
        ))

        try? context.save()
    }
}

/// Backs up and overrides this device's sharing identity while demo mode is active,
/// so the owner's People controls render against the seeded participants. Idempotent
/// and crash-safe: a backup is captured once on `activate()` and restored on
/// `deactivate()` (called from the app's launch/toggle task, which reconciles even
/// after a kill mid-demo).
enum DemoSession {
    private static let defaults = UserDefaults.standard
    private enum Key {
        static let active = "demo.overrideActive"
        static let bakRole = "demo.bak.syncRole"
        static let bakParticipant = "demo.bak.participantID"
    }

    @MainActor
    static func activate() {
        let prefs = LocalPrefs.shared
        if !defaults.bool(forKey: Key.active) {
            defaults.set(prefs.syncRole.rawValue, forKey: Key.bakRole)
            defaults.set(prefs.myParticipantID?.uuidString, forKey: Key.bakParticipant)
            defaults.set(true, forKey: Key.active)
        }
        prefs.syncRole = .owner
        prefs.myParticipantID = DemoData.ownerID
    }

    @MainActor
    static func deactivate() {
        guard defaults.bool(forKey: Key.active) else { return }
        let prefs = LocalPrefs.shared
        prefs.syncRole = SyncRole(rawValue: defaults.string(forKey: Key.bakRole) ?? "") ?? .solo
        prefs.myParticipantID = defaults.string(forKey: Key.bakParticipant).flatMap(UUID.init)
        defaults.removeObject(forKey: Key.active)
        defaults.removeObject(forKey: Key.bakRole)
        defaults.removeObject(forKey: Key.bakParticipant)
    }
}
