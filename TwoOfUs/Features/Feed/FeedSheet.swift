import SwiftUI
import SwiftData

/// Log a formula feed: an oz amount (presets + half-ounce custom) at a time.
struct FeedSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [SharedSettings]
    @Query private var babies: [Baby]

    /// Reports the logged event back to the host for the "Logged · Undo" toast.
    let onLogged: (String, @escaping () -> Void) -> Void

    @State private var amount: Double = 3
    @State private var customText = ""
    @State private var usingCustom = false
    @State private var date = Date()
    @State private var note = ""

    private var presets: [Double] { settingsList.first?.ozPresets ?? [2, 3, 4] }
    private var targetMinutes: Int { settingsList.first?.targetFeedIntervalMinutes ?? 180 }
    private var nextBottle: Date { date.addingTimeInterval(TimeInterval(targetMinutes * 60)) }
    private var canLog: Bool { amount > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("How much did \(babies.first?.name ?? "Baby") take?") {
                    HStack(spacing: 10) {
                        ForEach(presets, id: \.self) { oz in
                            presetChip(oz)
                        }
                    }
                    HStack {
                        Text("Custom")
                        Spacer()
                        TextField("oz", text: $customText)
                            .keyboardType(.decimalPad)
                            .textContentType(.none)   // no autofill suggestions over a number pad
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .onChange(of: customText) { _, new in
                                // Tolerate a pasted "5 oz" / stray spaces instead of
                                // silently rejecting anything Double() can't parse raw.
                                let cleaned = new.lowercased()
                                    .replacingOccurrences(of: "oz", with: "")
                                    .trimmingCharacters(in: .whitespaces)
                                if let v = Double(cleaned), v > 0 {
                                    amount = v
                                    usingCustom = true
                                }
                            }
                        Text("oz").foregroundStyle(AppColor.text3)
                    }
                }

                Section("Time") {
                    TimeControl(date: $date)
                }

                Section("Note") {
                    TextField("Add a note (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section {
                    Text("Next bottle reminder around \(TimeFormatting.clock(nextBottle))")
                        .font(.footnote)
                        .foregroundStyle(AppColor.text2)
                }
            }
            .navigationTitle("Log a feed 🍼")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log \(OzFormat.string(amount)) oz") { log() }
                        .disabled(!canLog)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func presetChip(_ oz: Double) -> some View {
        let selected = !usingCustom && amount == oz
        return Button {
            amount = oz
            usingCustom = false
            customText = ""
        } label: {
            VStack(spacing: 2) {
                Text(OzFormat.string(oz)).font(.system(.title2, design: .rounded).weight(.bold))
                Text("oz").font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(selected ? AppColor.accentFeed.opacity(0.25) : AppColor.card2, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppColor.accentFeed, lineWidth: selected ? 2 : 0)
            )
            .foregroundStyle(AppColor.text)
        }
        .buttonStyle(.plain)
    }

    private func log() {
        let store = EventStore(context: context)
        let event = store.logFeed(amountOz: amount, at: date, notes: note)
        Haptics.success()
        onLogged("Logged feed · \(OzFormat.string(amount)) oz") {
            store.softDelete(event)
        }
        dismiss()
    }
}
