import SwiftUI
import UIKit

/// "Miller's Week" — a shareable recap card rendered to an image to text the
/// grandparents. Built on the app's indigo "delight" gradient (the same surface
/// as the Stats record hero and the sleep Live Activity), so in-app and shared
/// art speak one visual language. Numbers come straight from `StatsEngine.weekRecap`.
struct WrappedCard: View {
    let recap: WeekRecap
    let babyName: String
    let ageText: String?

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                CradleMark(size: 72)
                Text("\(babyName.uppercased())'S WEEK")
                    .font(AppFont.hero(24))
                    .foregroundStyle(.white)
                Text(Self.range(recap.start, recap.end))
                    .font(.subheadline)
                    .foregroundStyle(AppColor.nightlightCream.opacity(0.8))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                metric("🍼", "\(recap.feedCount)", "bottles")
                metric("🥛", OzFormat.string(recap.totalOz.rounded()), "oz of milk")
                metric("💤", "\(Int((recap.totalSleep / 3600).rounded()))h", "of sleep")
                metric("💩", "\(recap.diaperCount)", "diapers")
            }

            VStack(spacing: 8) {
                if recap.longestStretch > 0 {
                    highlight("🏆", "Longest sleep", Self.durationShort(recap.longestStretch))
                }
                if let mvp = recap.nightMVP, !mvp.isEmpty {
                    highlight("🌙", "Night MVP", mvp)
                }
                if let hour = recap.hungriestHour {
                    highlight("🕕", "Hungriest hour", Self.hourLabel(hour))
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 2) {
                Text("Two of Us 🍼")
                    .font(AppFont.hero(15))
                    .foregroundStyle(.white)
                if let ageText {
                    Text(ageText)
                        .font(.caption)
                        .foregroundStyle(AppColor.nightlightCream.opacity(0.7))
                }
            }
        }
        .padding(28)
        .frame(width: 360, height: 640)
        .background(
            LinearGradient(colors: [AppColor.indigoHi, AppColor.indigoNight],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private func metric(_ emoji: String, _ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(emoji).font(.system(size: 28))
            Text(value)
                .font(AppFont.display(32))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(AppColor.nightlightCream.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
    }

    private func highlight(_ emoji: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(emoji)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(AppColor.nightlightCream.opacity(0.85))
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.06), in: Capsule())
    }

    // Self-contained formatting (the card renders off-screen for image export).

    private static func range(_ start: Date, _ end: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }

    private static func durationShort(_ seconds: TimeInterval) -> String {
        let mins = Int((seconds / 60).rounded())
        let h = mins / 60, m = mins % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private static func hourLabel(_ hour: Int) -> String {
        var c = DateComponents(); c.hour = hour
        let date = Calendar.current.date(from: c) ?? .now
        let f = DateFormatter(); f.dateFormat = "h a"
        return f.string(from: date)
    }
}

/// Presents the recap card and a Share button. Renders the card to a PNG on
/// appear (off-screen via `ImageRenderer`) so the share sheet hands Messages /
/// Photos a real image file.
struct WrappedShareView: View {
    let recap: WeekRecap
    let babyName: String
    let ageText: String?

    @Environment(\.dismiss) private var dismiss
    @State private var imageURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                WrappedCard(recap: recap, babyName: babyName, ageText: ageText)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
                    .padding(24)
            }
            .background(AppColor.bg)
            .navigationTitle("\(babyName)'s week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if let imageURL {
                        ShareLink(item: imageURL) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        ProgressView()
                    }
                }
            }
            .task { imageURL = renderToFile() }
        }
    }

    @MainActor
    private func renderToFile() -> URL? {
        let renderer = ImageRenderer(
            content: WrappedCard(recap: recap, babyName: babyName, ageText: ageText)
        )
        renderer.scale = 3   // ~1080×1920, crisp for sharing
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        let safeName = babyName.isEmpty ? "Baby" : babyName
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName)-week.png")
        do { try data.write(to: url); return url } catch { return nil }
    }
}
