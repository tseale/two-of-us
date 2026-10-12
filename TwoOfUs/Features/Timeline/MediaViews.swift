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

/// A photo burst as a little pile of polaroids: the newest on top, the ones
/// beneath peeking out slightly rotated and offset — photos layered on a
/// table, not a flat grid. The count badge rides the top corner; tapping the
/// row (HomeView) opens the swipeable pager. Three layers at most; the badge
/// carries the real total.
struct PhotoStack: View {
    /// Newest first — the order the timeline assembler builds.
    let events: [MediaEvent]

    /// Rotation/offset per depth: the deeper the photo, the further it leans
    /// out of the pile. Front stays nearly straight.
    private static let poses: [(angle: Double, offset: CGSize)] = [
        (-2, .zero),
        (4, CGSize(width: 5, height: -3)),
        (9, CGSize(width: 9, height: -6)),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(events.prefix(Self.poses.count).enumerated()).reversed(),
                    id: \.element.id) { index, event in
                polaroid(event)
                    .rotationEffect(.degrees(Self.poses[index].angle))
                    .offset(Self.poses[index].offset)
            }
        }
        .overlay(alignment: .topTrailing) {
            Text("\(events.count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(.black.opacity(0.55), in: Capsule())
                .offset(x: 6, y: -6)
        }
        .frame(width: 60, height: 54)
        .accessibilityHidden(true)   // the row's label already says "Photos (N)"
    }

    /// A thumbnail in a thin card frame with a whisper of shadow — the
    /// physical print the stack is pretending to be.
    private func polaroid(_ event: MediaEvent) -> some View {
        MediaThumbnail(event: event, size: 42)
            .padding(2)
            .background(AppColor.card, in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(AppColor.separator.opacity(0.6), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
    }
}

/// Full-size viewer, presented when a media row is tapped. Shows the image
/// (cached bytes first, then the remote URL), the staff caption, and the time.
struct MediaViewerSheet: View {
    /// The photos on view — one for a plain media row, the burst for a
    /// grouped row, swiped through as pages.
    let events: [MediaEvent]
    @Environment(\.dismiss) private var dismiss

    /// `.saved` shows the brief confirmation; `.acknowledged` is after it
    /// fades — the photo stays marked saved (no re-offer of the button), the
    /// toolbar just goes quiet.
    private enum SaveState: Equatable { case idle, saving, saved, acknowledged, failed(String) }
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
            // A status, not a control: plain muted text (no symbol, no
            // button chrome — a checkmark up here read as tappable), gone
            // after a moment. The state stays `.acknowledged`, so the Save
            // button doesn't re-offer itself for an already-saved photo.
            Text("Saved")
                .font(.subheadline)
                .foregroundStyle(AppColor.accentCheck.opacity(0.85))
                .transition(.opacity)
                .accessibilityLabel("Saved to camera roll")
                .task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(.easeOut(duration: 0.4)) {
                        saveStates[event.id] = .acknowledged
                    }
                }
        case .acknowledged:
            EmptyView()
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
