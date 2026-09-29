import Foundation

/// Anything that can be soft-deleted. Lives with the models (not EventStore)
/// so targets that compile `RecordMapping` without the app's store layer —
/// the watch app — get it too.
protocol SoftDeletable: AnyObject {
    var deletedAt: Date? { get set }
    var id: UUID { get }
}
extension FeedEvent: SoftDeletable {}
extension SleepEvent: SoftDeletable {}
extension DiaperEvent: SoftDeletable {}
extension NoteEvent: SoftDeletable {}
extension PlanSlot: SoftDeletable {}
extension PlanOverride: SoftDeletable {}
extension ActivityEvent: SoftDeletable {}
extension MediaEvent: SoftDeletable {}
extension CheckEvent: SoftDeletable {}
extension MedicationEvent: SoftDeletable {}
extension HealthCheckEvent: SoftDeletable {}
extension MoodEvent: SoftDeletable {}
extension PottyEvent: SoftDeletable {}
extension MilestoneEvent: SoftDeletable {}
extension StaffNoteEvent: SoftDeletable {}
