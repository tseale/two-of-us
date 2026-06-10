import SwiftUI

/// Natural-language quick-log sheet (iOS 26, on-device Foundation Models).
/// The user types something like "4oz bottle 20 minutes ago" or "wet diaper";
/// `MillerIntelligence` parses it and `onApply` performs the matching write.
struct NLLogSheet: View {
    /// Performs the actual log; called once the text parses to a known event.
    let onApply: (MillerIntelligence.ParsedLog) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var working = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Type what happened in plain words.")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.text2)
                TextField("e.g. “4oz 20 minutes ago”", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit(submit)
                if let error {
                    Text(error).font(.caption).foregroundStyle(AppColor.urgencyRed)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Quick log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log", action: submit).disabled(text.isEmpty || working)
                }
            }
            .overlay { if working { ProgressView().controlSize(.large) } }
            .onAppear { focused = true }
        }
    }

    private func submit() {
        let entry = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.isEmpty, !working else { return }
        working = true
        error = nil
        Task {
            let parsed = await MillerIntelligence.parseLog(entry, now: .now)
            working = false
            if let parsed {
                onApply(parsed)
                dismiss()
            } else {
                error = "Didn’t catch that — try “4oz 10 min ago” or “dirty diaper”."
            }
        }
    }
}
