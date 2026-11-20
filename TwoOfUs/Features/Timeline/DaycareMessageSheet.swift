import SwiftUI

/// The full text of a daycare message or staff note, chat-style: who wrote it
/// and when, the message in a bubble, then the rest of that day's messages
/// from daycare so a follow-up ("back to 99.1 after his nap") reads in
/// context. Read-only — replies happen in Brightwheel.
struct DaycareMessageSheet: View {
    let note: StaffNoteEvent
    /// Every staff note the caller already queries (newest first); the sheet
    /// picks that day's daycare messages out of it.
    let thread: [StaffNoteEvent]
    /// Media events the caller already queries; each message's attached
    /// photos are picked out by id (see `StaffNoteEvent.attachedPhotos`).
    var media: [MediaEvent] = []
    @Environment(\.dismiss) private var dismiss
    @State private var viewing: PhotoViewing?

    private struct PhotoViewing: Identifiable {
        let events: [MediaEvent]
        let start: Int
        var id: UUID { events[start].id }
    }

    private var dayMessages: [StaffNoteEvent] {
        let calendar = Calendar.current
        return thread
            .filter { $0.isFromDaycare && $0.deletedAt == nil
                && calendar.isDate($0.timestamp, inSameDayAs: note.timestamp)
                // Announcements and conversation don't mix: an announcement
                // opens alone, a message opens with the day's other messages.
                && $0.isAnnouncement == note.isAnnouncement }
            .sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(note.isAnnouncement ? [note] : dayMessages) { message in
                            bubble(message, selected: message.id == note.id)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .onAppear { proxy.scrollTo(note.id, anchor: .top) }
            }
            .background(AppColor.bg)
            .navigationTitle(note.isAnnouncement ? "Announcement" : "Daycare messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(item: $viewing) { viewing in
            // The viewer pages from its first event; lead with the tapped one.
            MediaViewerSheet(events: Array(viewing.events[viewing.start...] + viewing.events[..<viewing.start]))
        }
    }

    /// Attached photos under the bubble: one wide image when it's a single
    /// photo (the usual flyer), a row of square tiles for several.
    @ViewBuilder
    private func photos(_ photos: [MediaEvent]) -> some View {
        if photos.count == 1, let photo = photos.first {
            Button { viewing = PhotoViewing(events: photos, start: 0) } label: {
                WholePhoto(event: photo)
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(AppColor.separator.opacity(0.5), lineWidth: 0.5)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if photo.kind == .video {
                            Image(systemName: "play.fill")
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(.black.opacity(0.45), in: Circle())
                                .padding(8)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(photo.kind == .video ? "Attached video" : "Attached photo")
        } else if !photos.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 6)], spacing: 6) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    Button { viewing = PhotoViewing(events: photos, start: index) } label: {
                        MediaThumbnail(event: photo, size: 88, cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Attached \(photo.kind == .video ? "video" : "photo") \(index + 1) of \(photos.count)")
                }
            }
        }
    }

    private func bubble(_ message: StaffNoteEvent, selected: Bool) -> some View {
        let author = message.authorName.flatMap { $0.isEmpty ? nil : $0 } ?? "Daycare"
        let tint = message.isHealthNews ? AppColor.accentMedication : AppColor.accentNote
        return HStack(alignment: .top, spacing: 10) {
            Avatar(photoData: nil, name: author, colorHex: message.isHealthNews ? "FF6B6B" : "A8A0B8",
                   size: 32)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(author)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.text)
                    Text(TimeFormatting.clock(message.timestamp))
                        .font(.caption)
                        .foregroundStyle(AppColor.text3)
                    if message.isHealthNews {
                        Label("Health", systemImage: "thermometer.medium")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(tint)
                    }
                }
                let attached = message.attachedPhotos(in: media)
                Text(message.text)
                    .font(.callout)
                    .foregroundStyle(AppColor.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColor.card, in: .rect(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(tint.opacity(selected ? 0.6 : 0), lineWidth: 1.5)
                    }
                photos(attached)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
