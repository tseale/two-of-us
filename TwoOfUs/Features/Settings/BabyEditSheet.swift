import SwiftUI
import SwiftData
import PhotosUI

/// Focused editor for the baby's photo, name, and date of birth. Opened by
/// tapping the profile header (full role only). Commits through the sync-aware
/// `EventStore.updateBaby`.
struct BabyEditSheet: View {
    let baby: Baby

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var dob = Date()
    @State private var notBornYet = false
    @State private var photoData: Data?      // working copy; committed on Save
    @State private var photoItem: PhotosPickerItem?

    private var store: EventStore { EventStore(context: context) }

    /// Block Save on an empty name rather than silently keeping the old one — the
    /// user clearing the field and tapping Save shouldn't look like a no-op.
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 14) {
                        Avatar(photoData: photoData, name: name, colorHex: ParticipantColors.babyHex, size: 96)
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Text(photoData == nil ? "Add photo" : "Change photo")
                        }
                        if photoData != nil {
                            Button("Remove photo", role: .destructive) { photoData = nil }
                                .font(.footnote)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Name", text: $name)
                    Toggle("Not born just yet", isOn: $notBornYet)
                    DatePicker(notBornYet ? "Due date" : "Date of birth",
                               selection: $dob,
                               in: notBornYet ? Date()...Date.distantFuture
                                              : Date.distantPast...Date(),
                               displayedComponents: .date)
                } footer: {
                    if notBornYet {
                        Text("Once your baby arrives, turn this off and set their real birthday.")
                    }
                }
            }
            .navigationTitle("Edit baby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
            .onChange(of: photoItem) { _, item in loadPhoto(item) }
            // Keep the date inside the flipped range — the picker clamps its UI
            // but not the bound value.
            .onChange(of: notBornYet) { _, expecting in
                if expecting, dob <= .now {
                    dob = Calendar.current.date(byAdding: .weekOfYear, value: 4, to: .now) ?? .now
                } else if !expecting, dob > .now {
                    dob = .now
                }
            }
            .onAppear {
                name = baby.name
                dob = baby.dateOfBirth
                notBornYet = !baby.isBorn
                photoData = baby.photoData
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let raw = try? await item.loadTransferable(type: Data.self),
                  let scaled = ImageDownscale.avatar(from: raw) else { return }
            await MainActor.run { photoData = scaled }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }   // Save is disabled, but guard anyway
        store.updateBaby(name: trimmed, dateOfBirth: dob, photo: .some(photoData))
        dismiss()
    }
}
