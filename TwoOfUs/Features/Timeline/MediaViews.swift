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
    let event: MediaEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer(minLength: 0)
                fullImage
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
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColor.bg)
            .navigationTitle(event.kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var fullImage: some View {
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
                    unavailable
                default:
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
        } else {
            unavailable
        }
    }

    /// Signed CDN links expire — say so instead of spinning forever.
    private var unavailable: some View {
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
