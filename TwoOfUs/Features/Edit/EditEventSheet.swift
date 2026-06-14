import SwiftUI
import SwiftData

/// Edit any logged event. Saving creates a replacement record and soft-deletes
/// the original (append-only history), including an optional free-text note.
struct EditEventSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let entry: TimelineEntry

    @State private var date: Date
    @State private var amount: Double
    @State private var diaperType: DiaperType
    @State private var sleepStart: Date
    @State private var sleepEnd: Date
    @State private var notes: String

    init(entry: TimelineEntry) {
        self.entry = entry
        switch entry {
        case .feed(let e):
            _date = State(initialValue: e.timestamp)
            _amount = State(initialValue: e.amountOz)
            _diaperType = State(initialValue: .wet)
            _sleepStart = State(initialValue: e.timestamp)
            _sleepEnd = State(initialValue: e.timestamp)
            _notes = State(initialValue: e.notes ?? "")
        case .diaper(let e):
            _date = State(initialValue: e.timestamp)
            _amount = State(initialValue: 0)
            _diaperType = State(initialValue: e.type)
            _sleepStart = State(initialValue: e.timestamp)
            _sleepEnd = State(initialValue: e.timestamp)
            _notes = State(initialValue: e.notes ?? "")
        case .sleep(let e):
            _date = State(initialValue: e.startedAt)
            _amount = State(initialValue: 0)
            _diaperType = State(initialValue: .wet)
            _sleepStart = State(initialValue: e.startedAt)
            _sleepEnd = State(initialValue: e.endedAt ?? e.startedAt)
            _notes = State(initialValue: e.notes ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch entry {
                case .feed:
                    Section("Amount") {
                        // Range matches the store's bounds and steps by 0.25 so a
                        // 0.25 oz value (older data / NL parse) isn't clamped on edit.
                        Stepper(value: $amount, in: EventBounds.ozRange, step: 0.25) {
                            Text("\(OzFormat.string(amount)) oz")
                        }
                    }
                    Section("Time") { TimeControl(date: $date) }
                case .diaper:
                    Section("Type") {
                        Picker("Type", selection: $diaperType) {
                            ForEach(DiaperType.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    Section("Time") { TimeControl(date: $date, tint: AppColor.accentDiaper) }
                case .sleep:
                    Section("Asleep") {
                        DatePicker("Start", selection: $sleepStart, in: ...Date())
                        DatePicker("End", selection: $sleepEnd, in: sleepStart...Date())
                    } footer: {
                        if !sleepDurationValid {
                            Text("A sleep needs to last at least a minute.")
                                .foregroundStyle(AppColor.urgencyRed)
                        }
                    }
                }

                Section("Note") {
                    TextField("Add a note (optional)", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    Button(role: .destructive) { deleteOriginal() } label: {
                        Text("Delete entry")
                    }
                }
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveLabel) { save() }.disabled(!canSave)
                }
            }
        }
    }

    /// A completed sleep must span at least a minute — guards the 0-duration case
    /// the date pickers otherwise allow (end == start).
    private var sleepDurationValid: Bool {
        sleepEnd.timeIntervalSince(sleepStart) >= 60
    }

    private var canSave: Bool {
        if case .sleep = entry { return sleepDurationValid }
        return true
    }

    /// Contextual confirmation label so the action reads as what it edits.
    private var saveLabel: String {
        switch entry {
        case .feed: "Save feed"
        case .diaper: "Save change"
        case .sleep: "Save sleep"
        }
    }

    private func save() {
        let store = EventStore(context: context)
        switch entry {
        case .feed(let e): store.editFeed(e, amountOz: amount, timestamp: date, notes: notes)
        case .diaper(let e): store.editDiaper(e, type: diaperType, timestamp: date, notes: notes)
        case .sleep(let e): store.editSleep(e, startedAt: sleepStart, endedAt: sleepEnd, notes: notes)
        }
        Haptics.success()
        dismiss()
    }

    private func deleteOriginal() {
        let store = EventStore(context: context)
        switch entry {
        case .feed(let e): store.softDelete(e)
        case .diaper(let e): store.softDelete(e)
        case .sleep(let e): store.softDelete(e)
        }
        Haptics.warning()
        dismiss()
    }
}
