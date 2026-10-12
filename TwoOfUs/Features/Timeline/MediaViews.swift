import SwiftUI

/// Inline thumbnail for a MediaEvent row. Cached bytes render immediately;
/// otherwise the remote URL loads best-effort (Brightwheel's CDN links are
/// signed and can expire), and the fallback is a quiet placeholder — never a
/// broken-image glyph in the timeline.
struct MediaThumbnail: View {
    let event: MediaEvent
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let data = event.mediaData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let url = event.remoteURL.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(AppColor.separator.opacity(0.5), lineWidth: 0.5)
        }
        .overlay(alignment: .bottomTrailing) {
            if event.kind == .video {
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(.black.opacity(0.45), in: Circle())
                    .padding(2)
            }
        }
        .accessibilityHidden(true)   // the row's label already says photo/video
    }

    private var placeholder: some View {
        ZStack {
            AppColor.card2
            Image(systemName: event.kind == .video ? "video" : "photo")
                .font(.system(size: size * 0.4))
                .foregroundStyle(AppColor.text3)
        }
    }
}

/// Full-size viewer, presented when a media row is tapped. Shows the image
/// (cached bytes first, then the remote URL), the staff caption, and the time.
struct MediaViewerSheet: View {
    /// The photos on view — one for a plain media row, the burst for a
    /// grouped row, swiped through as pages.
    let events: [MediaEvent]
    @Environment(\.dismiss) private var dismiss

    private enum SaveState: Equatable { case idle, saving, saved, failed(String) }
    @State private var saveStates: [UUID: SaveState] = [:]
    @State private var selection = 0

    init(events: [MediaEvent]) { self.events = events }
    init(event: MediaEvent) { self.events = [event] }

    private var current: MediaEvent? {
        events.indices.contains(selection) ? events[selection] : events.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if events.count > 1 {
                    TabView(selection: $selection) {
                        ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                            page(for: event).tag(index)
                        }
                    }
                    .tabViewStyle(.page)
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                } else if let event = events.first {
                    page(for: event)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColor.bg)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Photos save to the camera roll; videos stream from the CDN
                // and have no local bytes to save (yet — byte caching is a
                // named later phase).
                if let current, current.kind == .photo {
                    ToolbarItem(placement: .topBarLeading) { saveButton(for: current) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var navigationTitle: String {
        guard events.count > 1 else { return events.first?.kind.label ?? "Photo" }
        return "Photo \(min(selection + 1, events.count)) of \(events.count)"
    }

    private func page(for event: MediaEvent) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            fullImage(for: event)
                .frame(maxWidth: .infinity)
            if let caption = event.caption, !caption.isEmpty {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Text(TimeFormatting.clock(event.timestamp))
                .font(.caption)
                .foregroundStyle(AppColor.text3)
            if case .failed(let message) = saveStates[event.id] ?? .idle {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(AppColor.urgencyAmber)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func saveButton(for event: MediaEvent) -> some View {
        switch saveStates[event.id] ?? .idle {
        case .idle, .failed:
            Button {
                Task { await save(event) }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .accessibilityLabel("Save photo to camera roll")
        case .saving:
            ProgressView()
        case .saved:
            Label("Saved", systemImage: "checkmark")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColor.accentCheck)
                .accessibilityLabel("Saved to camera roll")
        }
    }

    private func save(_ event: MediaEvent) async {
        saveStates[event.id] = .saving
        do {
            try await PhotoSaver.save(event)
            saveStates[event.id] = .saved
            Haptics.tap()
        } catch {
            saveStates[event.id] = .failed(error.localizedDescription)
        }
    }

    @ViewBuilder
    private func fullImage(for event: MediaEvent) -> some View {
        if let data = event.mediaData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else if let url = event.remoteURL.flatMap(URL.init(string:)) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    unavailable(for: event)
                default:
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
        } else {
            unavailable(for: event)
        }
    }

    /// Signed CDN links expire — say so instead of spinning forever.
    private func unavailable(for event: MediaEvent) -> some View {
        VStack(spacing: 8) {
            Image(systemName: event.kind == .video ? "video.slash" : "photo")
                .font(.largeTitle)
                .foregroundStyle(AppColor.text3)
            Text("This \(event.kind.label.lowercased()) isn't available anymore — Brightwheel's links expire. It's still in the Brightwheel app.")
                .font(.footnote)
                .foregroundStyle(AppColor.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}
