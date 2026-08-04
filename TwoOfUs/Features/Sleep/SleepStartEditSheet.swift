import SwiftUI

/// Backdates the start of an in-progress sleep — for when the baby fell
/// asleep before the timer was tapped. Only reachable for hand-logged
/// sessions; SNOO sessions carry an authoritative start time from the device.
struct SleepStartEditSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let sleep: SleepEvent

    @State private var startedAt: Date

    init(sleep: SleepEvent) {
        self.sleep = sleep
        _startedAt = State(initialValue: sleep.startedAt)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Fell asleep at") {
                    TimeControl(date: $startedAt, tint: AppColor.accentSleep)
                }
            }
            .navigationTitle("Edit Start Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .accessibilityIdentifier("sleepStartEditSheet.confirm")
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        let store = EventStore(context: context)
        store.editSleep(sleep, startedAt: startedAt, endedAt: nil, notes: sleep.notes)
        Haptics.success()
        dismiss()
    }
}
