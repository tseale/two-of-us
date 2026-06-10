import Foundation
import SwiftData

/// First-run seeding: creates the Baby, the owner Participant, and SharedSettings.
enum SeedData {
    /// True once a Baby exists (i.e. onboarding has been completed).
    static func isSeeded(in context: ModelContext) -> Bool {
        ((try? context.fetch(FetchDescriptor<Baby>()))?.isEmpty == false)
    }

    /// Used by previews/tests with sensible defaults.
    @MainActor
    static func seedIfNeeded(in context: ModelContext, babyName: String) {
        guard !isSeeded(in: context) else { return }
        createBaby(
            name: babyName,
            dateOfBirth: Calendar.current.date(byAdding: .weekOfYear, value: -12, to: .now) ?? .now,
            ownerName: "Alex",
            ownerColorHex: ParticipantColors.palette[0],
            in: context
        )
    }

    /// Creates the initial records during onboarding — the one atomic commit at
    /// the end of the flow (baby + owner profile + shared feeding settings).
    /// Main-actor: runs against the main context and pokes `SyncManager`.
    @MainActor
    @discardableResult
    static func createBaby(
        name: String,
        dateOfBirth: Date,
        babyPhoto: Data? = nil,
        ownerName: String,
        ownerColorHex: String,
        ownerPhoto: Data? = nil,
        targetFeedIntervalMinutes: Int = 180,
        ozPresets: [Double] = [2, 3, 4],
        in context: ModelContext
    ) -> Baby {
        let baby = Baby(name: name, dateOfBirth: dateOfBirth)
        baby.photoData = babyPhoto
        context.insert(baby)

        let owner = Participant(displayName: ownerName, colorHex: ownerColorHex, role: .full)
        owner.photoData = ownerPhoto
        context.insert(owner)
        // Remember who "me" is on this device (used to stamp logger identity and,
        // after sharing, to distinguish the two parents). Role stays .solo until
        // the owner actually invites a co-parent.
        LocalPrefs.shared.myParticipantID = owner.id

        let settings: SharedSettings
        if let existing = (try? context.fetch(FetchDescriptor<SharedSettings>()))?.first {
            settings = existing
        } else {
            settings = SharedSettings()
            context.insert(settings)
        }
        settings.targetFeedIntervalMinutes = targetFeedIntervalMinutes
        settings.ozPresets = ozPresets.sorted()
        // Keep the one-tap (widget/Siri) amount one of the presets; the largest
        // matches the shipped default ([2, 3, 4] → 4).
        settings.defaultFeedOz = settings.ozPresets.max() ?? settings.defaultFeedOz

        try? context.save()

        // These records were created *after* the sync engine's one-shot bootstrap
        // ran (at launch, against the then-empty store), so they must be enqueued
        // explicitly — otherwise they'd never upload and an invited co-parent
        // would join an empty zone. Optional-chained: previews/tests have no
        // SyncManager and demo mode runs against a throwaway store.
        if !LocalPrefs.shared.demoModeEnabled {
            SyncManager.shared?.enqueueSave([baby.id, owner.id, settings.id])
        }
        return baby
    }

    /// Seeds a week of illustrative events for SwiftUI previews (charts need data).
    /// No-op if any feed already exists. Attributes night feeds to "Mom" so the
    /// night-shift split renders.
    static func seedSampleEvents(in context: ModelContext, days: Int = 7) {
        guard let baby = try? context.fetch(FetchDescriptor<Baby>()).first else { return }
        if (try? context.fetch(FetchDescriptor<FeedEvent>()))?.isEmpty == false { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let now = Date()
        let mom = (name: "Mom", color: ParticipantColors.palette[3]) // pink
        let dad = (name: "Dad", color: ParticipantColors.palette[1]) // periwinkle

        func feed(_ oz: Double, _ date: Date, _ who: (name: String, color: String)) {
            guard date <= now else { return }
            context.insert(FeedEvent(
                baby: baby, amountOz: oz, timestamp: date,
                loggedByID: UUID(), loggedByName: who.name, loggedByColorHex: who.color
            ))
        }
        func sleep(_ start: Date, hours: Double, _ who: (name: String, color: String)) {
            guard start <= now else { return }
            context.insert(SleepEvent(
                baby: baby, startedAt: start, endedAt: min(now, start.addingTimeInterval(hours * 3600)),
                loggedByID: UUID(), loggedByName: who.name, loggedByColorHex: who.color
            ))
        }
        func diaper(_ type: DiaperType, _ date: Date) {
            guard date <= now else { return }
            context.insert(DiaperEvent(
                baby: baby, type: type, timestamp: date,
                loggedByID: UUID(), loggedByName: dad.name, loggedByColorHex: dad.color
            ))
        }

        for d in 0..<days {
            guard let dayStart = cal.date(byAdding: .day, value: -d, to: today) else { continue }

            // Daytime feeds ~ every 3h, night feed ~2am (Mom).
            for h in stride(from: 6, through: 21, by: 3) {
                let date = dayStart.addingTimeInterval(Double(h) * 3600 + Double((h * 11) % 40) * 60)
                feed(2.5 + Double((h / 3) % 3) * 0.5, date, h >= 19 ? mom : dad)
            }
            feed(3, dayStart.addingTimeInterval(2 * 3600), mom)

            // Night stretch grows with recency; plus an afternoon nap.
            let stretch = 3.0 + Double(days - 1 - d) * 0.45
            sleep(dayStart.addingTimeInterval(22 * 3600), hours: stretch, dad)
            sleep(dayStart.addingTimeInterval(13 * 3600), hours: 1.5, dad)

            // Diapers ~ every 4h.
            for h in stride(from: 5, through: 21, by: 4) {
                diaper(h % 8 == 0 ? .both : (h % 3 == 0 ? .dirty : .wet),
                       dayStart.addingTimeInterval(Double(h) * 3600))
            }
        }

        try? context.save()
    }
}
