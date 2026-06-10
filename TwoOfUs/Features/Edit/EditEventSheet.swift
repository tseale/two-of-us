import SwiftUI
import SwiftData

/// Edit any logged event. Saving creates a replacement record and soft-deletes
/// the original (append-only history). No notes UI this increment.
struct EditEventSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let entry: TimelineEntry

    @State private var date: Date
    @State private var amount: Double
    @State private var diaperType: DiaperType
    @State private var sleepStart: Date
    @State private var sleepEnd: Date

    init(entry: TimelineEntry) {
        self.entry = entry
        switch entry {
        case .feed(let e):
            _date = State(initialValue: e.timestamp)
            _amount = State(initialValue: e.amountOz)
            _diaperType = State(initialValue: .wet)
            _sleepStart = State(initialValue: e.timestamp)
            _sleepEnd = State(initialValue: e.timestamp)
        case .diaper(let e):
            _date = State(initialValue: e.timestamp)
            _amount = State(initialValue: 0)
            _diaperType = State(initialValue: e.type)
            _sleepStart = State(initialValue: e.timestamp)
            _sleepEnd = State(initialValue: e.timestamp)
        case .sleep(let e):
            _date = State(initialValue: e.startedAt)
            _amount = State(initialValue: 0)
            _diaperType = State(initialValue: .wet)
            _sleepStart = State(initialValue: e.startedAt)
            _sleepEnd = State(initialValue: e.endedAt ?? e.startedAt)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch entry {
                case .feed:
                    Section("Amount") {
                        Stepper(value: $amount, in: 0.5...12, step: 0.5) {
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
                    Section("Time") { TimeControl(date: $date) }
                case .sleep:
                    Section("Asleep") {
                        DatePicker("Start", selection: $sleepStart, in: ...Date())
                        DatePicker("End", selection: $sleepEnd, in: sleepStart...Date())
                    }
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
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
        }
    }

    private func save() {
        let store = EventStore(context: context)
        switch entry {
        case .feed(let e): store.editFeed(e, amountOz: amount, timestamp: date)
        case .diaper(let e): store.editDiaper(e, type: diaperType, timestamp: date)
        case .sleep(let e): store.editSleep(e, startedAt: sleepStart, endedAt: sleepEnd)
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
