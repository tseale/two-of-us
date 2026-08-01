import SwiftUI
import SwiftData

/// Edit any logged event. Saving creates a replacement record and soft-deletes
/// the original (append-only history), including an optional free-text note.
struct EditEventSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let entry: TimelineEntry

    @Query private var participants: [Participant]

    @State private var date: Date
    @State private var amount: Double
    @State private var diaperType: DiaperType
    @State private var sleepStart: Date
    @State private var sleepEnd: Date
    @State private var notes: String
    @State private var loggedByID: UUID
    @State private var showDeleteConfirm = false

    init(entry: TimelineEntry) {
        self.entry = entry
        _loggedByID = State(initialValue: entry.loggedByID)
        switch entry {
        case .feed(let e):
            _date = State(initialValue: e.timestamp)
            // Legacy zero-ounce rows open at the stepper's floor so saving the
            // edit always produces a loggable amount.
            _amount = State(initialValue: max(e.amountOz, 0.25))
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
                    Section {
                        // Lower bound 0.25, not 0: stepping down to "0 oz" and
                        // saving minted an attributed zero-ounce ghost row that
                        // no sweep could remove. Steps by 0.25 so a 0.25 oz
                        // value (older data / NL parse) isn't clamped on edit.
                        Stepper(value: $amount, in: 0.25...EventBounds.ozRange.upperBound, step: 0.25) {
                            Text("\(OzFormat.string(amount)) oz")
                        }
                    } header: {
                        Text("Amount")
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
                    // Section can't take a String title *and* a footer in one
                    // initializer — use the header closure so both coexist.
                    Section {
                        DatePicker("Start", selection: $sleepStart, in: ...Date())
                        DatePicker("End", selection: $sleepEnd, in: sleepStart...Date())
                    } header: {
                        Text("Asleep")
                    } footer: {
                        if !sleepDurationValid {
                            Text("A sleep needs to last at least a minute.")
                                .foregroundStyle(AppColor.urgencyRed)
                        }
                    }
                }

                // Reassigning is common enough to live in the sheet: one parent
                // logs what the other actually did (or fixes a ghost-attributed
                // row). Hidden with a single participant — nothing to change.
                if activeParticipants.count > 1 {
                    Section("Logged by") {
                        Picker("Logged by", selection: $loggedByID) {
                            ForEach(activeParticipants) { p in
                                Text(p.displayName).tag(p.id)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section("Note") {
                    TextField("Add a note (optional)", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
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
            .confirmationDialog("Delete this entry?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete entry", role: .destructive) { deleteOriginal() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the logged event from the timeline and your stats.")
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

    private var activeParticipants: [Participant] {
        participants.filter(\.isActive).sorted { $0.invitedAt < $1.invitedAt }
    }

    /// The picked participant, only when it's an actual change — unchanged (or
    /// unresolvable) attribution passes nil so the edit keeps the original's.
    private var newLogger: Participant? {
        guard loggedByID != entry.loggedByID else { return nil }
        return activeParticipants.first { $0.id == loggedByID }
    }

    private func save() {
        let store = EventStore(context: context)
        switch entry {
        case .feed(let e):
            store.editFeed(e, amountOz: amount, timestamp: date, notes: notes, loggedBy: newLogger)
        case .diaper(let e):
            store.editDiaper(e, type: diaperType, timestamp: date, notes: notes, loggedBy: newLogger)
        case .sleep(let e):
            store.editSleep(e, startedAt: sleepStart, endedAt: sleepEnd, notes: notes, loggedBy: newLogger)
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
