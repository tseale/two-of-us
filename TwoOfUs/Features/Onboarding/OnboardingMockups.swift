import SwiftUI

/// Pure-SwiftUI miniatures of the system surfaces the app lives on — a widget,
/// the Dynamic Island mid-sleep, a Siri phrase, a Control Center control — plus
/// little chart/stat cards for the "it learns your rhythm" page. No screenshots;
/// everything is drawn with the design system so it matches both schemes.
/// Decorative only: pages hide them from accessibility and speak a summary.

// MARK: - "Everywhere you are"

/// The Dynamic Island during an active sleep: moon + live timer.
struct MockDynamicIsland: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.fill")
                .font(.subheadline)
                .foregroundStyle(AppColor.accentSleep)
            Spacer()
            Text("1:24:05")
                .font(AppFont.display(17, relativeTo: .body))
                .foregroundStyle(AppColor.accentSleep)
        }
        .padding(.horizontal, 16)
        .frame(width: 210, height: 42)
        .background(Capsule().fill(.black))
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
    }
}

/// A small "time since last feed" widget.
struct MockSmallWidget: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("🍼").font(.system(size: 22))
            Spacer(minLength: 0)
            Text("Since feed").sectionLabelStyle()
            Text("2h 40m")
                .font(AppFont.display(24, relativeTo: .title2))
                .foregroundStyle(AppColor.text)
        }
        .padding(14)
        .frame(width: 124, height: 124, alignment: .leading)
        .surfaceCard(cornerRadius: 26)
    }
}

/// A Siri phrase chip.
struct MockSiriChip: View {
    var phrase = "“Log a four ounce bottle”"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.headline)
                .foregroundStyle(
                    LinearGradient(colors: [AppColor.accentSleep, AppColor.accentFeed],
                                   startPoint: .leading, endPoint: .trailing)
                )
            Text(phrase)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColor.text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .surfaceCard(cornerRadius: 22)
    }
}

/// A Control Center control: round toggle + label.
struct MockControlToggle: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(AppColor.accentSleep))
            Text("Sleep")
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppColor.text2)
        }
    }
}

// MARK: - "It learns your rhythm"

/// A believable sample day rendered with the real ribbon component.
struct MockRibbonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today, at a glance").sectionLabelStyle()
            DayRibbonView(marks: Self.sampleMarks, day: .now, showNowMarker: false)
                .frame(height: 44)
            HStack(spacing: 14) {
                legendDot(AppColor.accentFeed, "feeds")
                legendDot(AppColor.accentSleep, "sleep")
                legendDot(AppColor.accentDiaper, "diapers")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption2).foregroundStyle(AppColor.text3)
        }
    }

    static var sampleMarks: [RibbonMark] {
        let start = Calendar.current.startOfDay(for: .now)
        func at(_ h: Double) -> Date { start.addingTimeInterval(h * 3600) }
        return [
            RibbonMark(kind: .sleep, start: at(0), end: at(4.5)),
            RibbonMark(kind: .feed, start: at(4.6)),
            RibbonMark(kind: .diaper, start: at(4.9)),
            RibbonMark(kind: .sleep, start: at(5.3), end: at(7.4)),
            RibbonMark(kind: .feed, start: at(7.5)),
            RibbonMark(kind: .feed, start: at(10.4)),
            RibbonMark(kind: .diaper, start: at(10.7)),
            RibbonMark(kind: .sleep, start: at(12.6), end: at(14.2)),
            RibbonMark(kind: .feed, start: at(14.3)),
            RibbonMark(kind: .diaper, start: at(16.8)),
            RibbonMark(kind: .feed, start: at(17.2)),
            RibbonMark(kind: .sleep, start: at(19.4), end: at(20.6)),
            RibbonMark(kind: .feed, start: at(20.8)),
            RibbonMark(kind: .sleep, start: at(21.6), end: at(24)),
        ]
    }
}

/// A rising sleep-consolidation trend, the line drawing itself in on arrival.
struct MockTrendCard: View {
    /// 0…1 — the host page flips this to 1 when the page is revealed.
    var progress: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let points: [CGFloat] = [0.30, 0.42, 0.38, 0.55, 0.60, 0.74, 0.88]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Longest sleep stretch").sectionLabelStyle()
            trend
                .frame(height: 64)
            Text("6h 12m last night — and climbing")
                .font(.caption)
                .foregroundStyle(AppColor.text3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
    }

    private var trend: some View {
        GeometryReader { geo in
            let pts = points.enumerated().map { i, v in
                CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(points.count - 1),
                        y: geo.size.height * (1 - v))
            }
            ZStack {
                areaPath(pts, in: geo.size)
                    .fill(
                        LinearGradient(colors: [AppColor.accentSleep.opacity(0.25),
                                                AppColor.accentSleep.opacity(0)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .opacity(reduceMotion ? 1 : Double(progress))
                linePath(pts)
                    .trim(from: 0, to: reduceMotion ? 1 : progress)
                    .stroke(AppColor.accentSleep,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.8).delay(0.3), value: progress)
        }
    }

    private func linePath(_ pts: [CGPoint]) -> Path {
        var p = Path()
        guard let first = pts.first else { return p }
        p.move(to: first)
        for pt in pts.dropFirst() { p.addLine(to: pt) }
        return p
    }

    private func areaPath(_ pts: [CGPoint], in size: CGSize) -> Path {
        var p = linePath(pts)
        guard let last = pts.last, let first = pts.first else { return p }
        p.addLine(to: CGPoint(x: last.x, y: size.height))
        p.addLine(to: CGPoint(x: first.x, y: size.height))
        p.closeSubpath()
        return p
    }
}

/// The Stats tab's beloved "who got up more" callout, in miniature.
struct MockNightMVPCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("👑").font(.system(size: 26))
            VStack(alignment: .leading, spacing: 2) {
                Text("Night MVP this week").sectionLabelStyle()
                Text("Mom — 9 night feeds")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(AppColor.text)
            }
            Spacer()
            Circle()
                .fill(Color(hex: "FF8FA3"))
                .frame(width: 32, height: 32)
                .overlay {
                    Text("M")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
    }
}

// MARK: - Previews

#Preview("Everywhere collage") {
    VStack(spacing: 18) {
        MockDynamicIsland()
        HStack(spacing: 18) {
            MockSmallWidget()
            MockControlToggle()
        }
        MockSiriChip()
    }
    .padding(28)
    .background(AppColor.bg)
}

#Preview("Rhythm cards · dark") {
    VStack(spacing: 14) {
        MockRibbonCard()
        MockTrendCard()
        MockNightMVPCard()
    }
    .padding(28)
    .background(AppColor.bg)
    .preferredColorScheme(.dark)
}
