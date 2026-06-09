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
    @State private var photoData: Data?      // working copy; committed on Save
    @State private var photoItem: PhotosPickerItem?

    private var store: EventStore { EventStore(context: context) }

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
                    DatePicker("Date of birth", selection: $dob,
                               in: ...Date(), displayedComponents: .date)
                }
            }
            .navigationTitle("Edit baby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onChange(of: photoItem) { _, item in loadPhoto(item) }
            .onAppear {
                name = baby.name
                dob = baby.dateOfBirth
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
        store.updateBaby(name: trimmed.isEmpty ? baby.name : trimmed,
                         dateOfBirth: dob,
                         photo: .some(photoData))
        dismiss()
    }
}
