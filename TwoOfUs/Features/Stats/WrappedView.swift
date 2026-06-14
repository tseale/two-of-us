import SwiftUI
import UIKit

/// Range options for the shareable recap.
enum WrappedRange: String, CaseIterable, Identifiable {
    case week, month
    var id: String { rawValue }
    var days: Int { self == .week ? 7 : 30 }
    var label: String { self == .week ? "Week" : "Month" }
    var titleWord: String { self == .week ? "WEEK" : "MONTH" }
    var periodWord: String { self == .week ? "this week" : "this month" }
}

/// "Miller's Week/Month" — a shareable recap card rendered to an image to text
/// the grandparents. Built on the app's indigo "delight" gradient (the same
/// surface as the Stats record hero and the sleep Live Activity), so in-app and
/// shared art speak one visual language. Numbers come from `StatsEngine.weekRecap`.
struct WrappedCard: View {
    let recap: WeekRecap
    let range: WrappedRange
    let babyName: String
    let ageText: String?
    let babyPhoto: Data?
    /// "Tracked by Taylor & Katie" — the caregiver credit, when known.
    let credit: String?

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                header
                Text("\(babyName.uppercased())'S \(range.titleWord)")
                    .font(AppFont.hero(23))
                    .foregroundStyle(.white)
                Text(Self.range(recap.start, recap.end))
                    .font(.subheadline)
                    .foregroundStyle(AppColor.nightlightCream.opacity(0.8))
            }

            if let milestone = recap.milestone {
                milestoneBanner(milestone)
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
                if let credit {
                    Text(credit)
                        .font(.caption)
                        .foregroundStyle(AppColor.nightlightCream.opacity(0.8))
                }
                if let ageText {
                    Text(ageText)
                        .font(.caption2)
                        .foregroundStyle(AppColor.nightlightCream.opacity(0.6))
                }
            }
        }
        .padding(28)
        .frame(width: 360, height: 660)
        .background(
            LinearGradient(colors: [AppColor.indigoHi, AppColor.indigoNight],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    /// The baby's photo when set (with a soft ring), else the brand CradleMark.
    @ViewBuilder private var header: some View {
        if babyPhoto != nil {
            Avatar(photoData: babyPhoto, name: babyName,
                   colorHex: ParticipantColors.babyHex, size: 76)
                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 2))
        } else {
            CradleMark(size: 72)
        }
    }

    private func milestoneBanner(_ m: Milestone) -> some View {
        HStack(spacing: 10) {
            Text("🎉").font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text("milestone \(range.periodWord)")
                    .font(.caption2)
                    .foregroundStyle(AppColor.nightlightCream.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
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

/// Presents the recap card with a Week/Month toggle and a Share button. Renders
/// the card to a PNG (off-screen via `ImageRenderer`) so the share sheet hands
/// Messages / Photos a real image file. Re-renders when the range flips.
struct WrappedShareView: View {
    let engine: StatsEngine
    let babyName: String
    let ageText: String?
    let babyPhoto: Data?

    @Environment(\.dismiss) private var dismiss
    @State private var range: WrappedRange = .week
    @State private var imageURL: URL?

    private var recap: WeekRecap { engine.weekRecap(days: range.days) }

    /// "Tracked by Taylor & Katie", from the all-time caregiver list.
    private var credit: String? {
        let names = engine.contributions()
            .map(\.name)
            .filter { !$0.isEmpty && $0 != "Unknown" }
        guard !names.isEmpty else { return nil }
        return "Tracked by " + names.formatted(.list(type: .and))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Picker("Range", selection: $range) {
                        ForEach(WrappedRange.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 24)

                    card
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
            }
            .background(AppColor.bg)
            .navigationTitle("\(babyName)'s recap")
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
            // Re-render the export whenever the range flips.
            .task(id: range) {
                imageURL = nil
                imageURL = renderToFile()
            }
        }
    }

    private var card: WrappedCard {
        WrappedCard(recap: recap, range: range, babyName: babyName,
                    ageText: ageText, babyPhoto: babyPhoto, credit: credit)
    }

    @MainActor
    private func renderToFile() -> URL? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3   // ~1080×1980, crisp for sharing
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        let safeName = babyName.isEmpty ? "Baby" : babyName
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName)-\(range.rawValue).png")
        do { try data.write(to: url); return url } catch { return nil }
    }
}
