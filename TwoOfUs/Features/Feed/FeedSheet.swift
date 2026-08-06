import SwiftUI
import SwiftData

/// Log a formula feed: an oz amount at a time.
///
/// The default amount IS the bottle that was made — the most the baby will
/// take — so the quick chips are the bottle itself plus quarter-ounce steps
/// DOWN from it ("he left a little"); the custom field covers everything else.
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

    /// The bottle size (Settings → Feeding & Tracking → default amount).
    private var bottleOz: Double {
        let oz = settingsList.first?.defaultFeedOz ?? 4
        return oz > 0 ? min(oz, 32) : 4
    }

    /// Bottle first (so the sheet always opens with a chip highlighted), then
    /// the first quarter-ounce steps down that are still loggable.
    private var presets: [Double] {
        [bottleOz] + stride(from: bottleOz - 0.25, through: bottleOz - 0.75, by: -0.25)
            .filter { $0 >= 0.5 }
    }
    private var nextBottle: Date {
        date.addingTimeInterval(settingsList.first?.feedInterval(after: date) ?? TimeInterval(180 * 60))
    }
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
                        // Placeholder is a value hint, not "oz" — the trailing unit
                        // label already says oz (else an empty field reads "oz  oz").
                        TextField("0", text: $customText)
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
                                } else if cleaned.isEmpty {
                                    // Field was cleared — revert to preset-selection mode so
                                    // the last selected chip re-highlights instead of showing
                                    // no selection while the button still carries a stale amount.
                                    usingCustom = false
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
                        .accessibilityIdentifier("feedSheet.confirm")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // Open on the bottle size — it's the first chip, so the sheet always
        // opens with a highlighted chip and is one Log tap from the common case
        // (he finished the bottle).
        .onAppear {
            guard !usingCustom else { return }
            amount = bottleOz
        }
    }

    private func presetChip(_ oz: Double) -> some View {
        let selected = !usingCustom && amount == oz
        return Button {
            amount = oz
            usingCustom = false
            customText = ""
            Haptics.tap()
        } label: {
            VStack(spacing: 2) {
                // "3.75" is wider than the old whole-oz labels — scale, don't wrap.
                Text(OzFormat.string(oz))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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
        // A refused log (no attributable owner, bad amount) already surfaced a
        // banner via StoreErrorCenter — just close without a success toast.
        guard let event = store.logFeed(amountOz: amount, at: date, notes: note) else {
            dismiss()
            return
        }
        Haptics.success()
        onLogged("Logged feed · \(OzFormat.string(amount)) oz") {
            store.softDelete(event)
        }
        dismiss()
    }
}
