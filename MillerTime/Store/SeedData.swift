import Foundation
import SwiftData

/// First-run seeding: creates the Baby, the owner Participant, and SharedSettings.
enum SeedData {
    /// True once a Baby exists (i.e. onboarding has been completed).
    static func isSeeded(in context: ModelContext) -> Bool {
        ((try? context.fetch(FetchDescriptor<Baby>()))?.isEmpty == false)
    }

    /// Used by previews/tests with sensible defaults.
    static func seedIfNeeded(in context: ModelContext, babyName: String) {
        guard !isSeeded(in: context) else { return }
        createBaby(
            name: babyName,
            dateOfBirth: Calendar.current.date(byAdding: .weekOfYear, value: -12, to: .now) ?? .now,
            ownerName: "Taylor",
            ownerColorHex: ParticipantColors.palette[0],
            in: context
        )
    }

    /// Creates the initial records during onboarding.
    @discardableResult
    static func createBaby(
        name: String,
        dateOfBirth: Date,
        ownerName: String,
        ownerColorHex: String,
        in context: ModelContext
    ) -> Baby {
        let baby = Baby(name: name, dateOfBirth: dateOfBirth)
        context.insert(baby)

        let owner = Participant(displayName: ownerName, colorHex: ownerColorHex, role: .full)
        context.insert(owner)

        if (try? context.fetch(FetchDescriptor<SharedSettings>()))?.isEmpty != false {
            context.insert(SharedSettings())
        }

        try? context.save()
        return baby
    }
}
