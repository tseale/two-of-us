import SwiftUI
import SwiftData
import PhotosUI

/// Focused editor for the local user's own avatar, name, and color. Opened from
/// the "You" row. Commits through `EventStore.updateMyProfile`, which also
/// backfills the new name/color onto past timeline entries.
struct ProfileEditSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var colorHex = ParticipantColors.palette[0]
    @State private var photoData: Data?
    @State private var photoItem: PhotosPickerItem?
    /// The stored values load once per presentation: `onAppear` can fire
    /// again while the sheet is up (e.g. iPhone Duo opening or closing), and
    /// reloading then would wipe unsaved edits.
    @State private var seeded = false

    private var store: EventStore { EventStore(context: context) }

    /// Block Save on an empty name instead of silently dismissing — a cleared
    /// field tapping Save shouldn't read as success.
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 14) {
                        Avatar(photoData: photoData, name: name, colorHex: colorHex, size: 96)
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
                    TextField("Your name", text: $name)
                }

                Section("Your color") {
                    ParticipantColorPicker(selection: $colorHex, label: "Color")
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
            .onChange(of: photoItem) { _, item in loadPhoto(item) }
            .onAppear {
                // Not marked seeded until the profile resolves, so a later
                // appearance still loads it if it was missing (as before).
                guard !seeded, let me = store.owner else { return }
                seeded = true
                name = me.displayName
                colorHex = me.colorHex.isEmpty ? ParticipantColors.palette[0] : me.colorHex
                photoData = me.photoData
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
        store.updateMyProfile(name: trimmed, colorHex: colorHex, photo: .some(photoData))
        dismiss()
    }
}
