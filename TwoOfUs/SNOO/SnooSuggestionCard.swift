import SwiftUI
import SwiftData

/// One SNOO suggestion on the logging surface (§8). Two shapes: a completed
/// session ("Save session") and an in-progress one ("Start from <time>").
/// The card only ever proposes — every write goes through an explicit tap.
struct SnooSuggestionCard: View {
    @Environment(\.modelContext) private var context
    @State private var coordinator = SnooSyncCoordinator.shared
    @State private var editing = false

    let suggestion: SnooSuggestion
    /// Provided by the parent so the card's elapsed text is computed at
    /// render, not ticking live (§8).
    let now: Date
    var onSaved: ((String) -> Void)?

    private var store: EventStore { EventStore(context: context) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "bed.double.fill")
                    .font(.footnote)
                    .foregroundStyle(AppColor.accentSleep)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.text)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(AppColor.text2)
                }
                Spacer(minLength: 8)
                Button {
                    coordinator.dismiss(suggestion)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.text3)
                        .frame(width: 28, height: 28)
                        .background(AppColor.card2, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss suggestion")
                .accessibilityHint("This SNOO session won't be suggested again")
            }

            HStack(spacing: 10) {
                Button(acceptLabel) { accept() }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(AppColor.accentSleep)
                Button("Edit") { editing = true }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(AppColor.accentSleep)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .surfaceCard(cornerRadius: 14)
        .sheet(isPresented: $editing) {
            SnooSuggestionEditSheet(suggestion: suggestion, onSaved: onSaved)
        }
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        switch suggestion.kind {
        case .completed: "SNOO recorded a sleep session"
        case .inProgress: "SNOO has been running since \(TimeFormatting.clock(suggestion.startedAt))"
        }
    }

    private var detail: String {
        switch suggestion.kind {
        case .completed(let endedAt):
            let range = "\(TimeFormatting.clock(suggestion.startedAt))–\(TimeFormatting.clock(endedAt))"
            return "\(range) · \(TimeFormatting.duration(from: suggestion.startedAt, to: endedAt))"
        case .inProgress:
            return "Start a sleep session from then? (\(TimeFormatting.duration(from: suggestion.startedAt, to: now)) ago)"
        }
    }

    private var acceptLabel: String {
        switch suggestion.kind {
        case .completed: "Save session"
        case .inProgress: "Start from \(TimeFormatting.clock(suggestion.startedAt))"
        }
    }

    private func accept() {
        guard coordinator.accept(suggestion, store: store) else { return }
        Haptics.success()
        switch suggestion.kind {
        case .completed(let endedAt):
            onSaved?("Saved \(TimeFormatting.duration(from: suggestion.startedAt, to: endedAt)) of sleep")
        case .inProgress:
            onSaved?("Sleep started from \(TimeFormatting.clock(suggestion.startedAt))")
        }
    }
}

/// The suggestion's "Edit" path: the sleep editor pre-filled with the SNOO
/// times (§8). Saving writes a fresh record through the store and marks the
/// session imported — the original suggestion never resurfaces.
struct SnooSuggestionEditSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator = SnooSyncCoordinator.shared

    let suggestion: SnooSuggestion
    var onSaved: ((String) -> Void)?

    @State private var start: Date
    @State private var end: Date
    @State private var notes = ""

    init(suggestion: SnooSuggestion, onSaved: ((String) -> Void)? = nil) {
        self.suggestion = suggestion
        self.onSaved = onSaved
        _start = State(initialValue: suggestion.startedAt)
        _end = State(initialValue: suggestion.endedAt ?? .now)
    }

    private var isInProgress: Bool {
        if case .inProgress = suggestion.kind { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Start", selection: $start, in: ...Date())
                    if !isInProgress {
                        DatePicker("End", selection: $end, in: start...Date())
                    }
                } header: {
                    Text("Asleep")
                } footer: {
                    if isInProgress {
                        Text("Starts the sleep timer from this time.")
                    } else if !durationValid {
                        Text("A sleep needs to last at least a minute.")
                            .foregroundStyle(AppColor.urgencyRed)
                    }
                }

                Section("Note") {
                    TextField("Add a note (optional)", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle("SNOO session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isInProgress ? "Start sleep" : "Save sleep") { save() }
                        .disabled(!isInProgress && !durationValid)
                }
            }
        }
    }

    private var durationValid: Bool {
        end.timeIntervalSince(start) >= 60
    }

    private func save() {
        let store = EventStore(context: context)
        let saved: Bool
        if isInProgress {
            saved = store.startSleep(at: start, source: .snoo) != nil
            if saved { onSaved?("Sleep started from \(TimeFormatting.clock(start))") }
        } else {
            saved = store.logCompletedSleep(startedAt: start, endedAt: end,
                                            notes: notes.isEmpty ? nil : notes,
                                            source: .snoo) != nil
            if saved { onSaved?("Saved \(TimeFormatting.duration(from: start, to: end)) of sleep") }
        }
        guard saved else { return }
        coordinator.markImported(suggestion)
        Haptics.success()
        dismiss()
    }
}
