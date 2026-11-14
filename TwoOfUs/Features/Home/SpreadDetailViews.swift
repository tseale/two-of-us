import SwiftUI
import Charts

// The building blocks of the leading page of Home's spread (iPhone Duo open
// in landscape) that are more than a card of text. Each one is flexible: it
// takes whatever height its page leaves, so the page ends on the foot line.

// MARK: - A week of nights

/// The last several nights drawn to scale, one row each, the newest at the
/// bottom: his sleep as bars across the night window, each bottle a dot.
/// Rows share the height they are given, so the chart fills its card.
struct NightsChart: View {
    struct Row: Identifiable {
        var id: Date { night.start }
        /// The whole night window (what the row scales to).
        let night: DateInterval
        let segments: [DateInterval]
        let feedTimes: [Date]
        let asleep: TimeInterval
        /// The night the page is about (drawn brighter, labelled in full).
        let isCurrent: Bool
    }

    let rows: [Row]

    private let labelWidth: CGFloat = 34
    private let totalWidth: CGFloat = 52

    var body: some View {
        VStack(spacing: 6) {
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Text(row.night.start.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption.weight(row.isCurrent ? .bold : .regular))
                        .foregroundStyle(row.isCurrent ? AppColor.text : AppColor.text3)
                        .frame(width: labelWidth, alignment: .leading)
                    track(row)
                    Text(row.asleep > 0 ? Self.duration(row.asleep) : "—")
                        .font(.caption.monospacedDigit().weight(row.isCurrent ? .bold : .regular))
                        .foregroundStyle(row.isCurrent ? AppColor.accentSleep : AppColor.text3)
                        .frame(width: totalWidth, alignment: .trailing)
                }
                .frame(maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText(row))
            }
            axis
        }
    }

    private func track(_ row: Row) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = min(max(geo.size.height * 0.55, 8), 18)
            let length = max(row.night.duration, 1)
            let x: (Date) -> CGFloat = { date in
                CGFloat(min(max(date.timeIntervalSince(row.night.start) / length, 0), 1)) * width
            }
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppColor.card2)
                    .frame(width: width, height: height)
                ForEach(row.segments, id: \.start) { segment in
                    Capsule()
                        .fill(AppColor.accentSleep.opacity(row.isCurrent ? 1 : 0.5))
                        .frame(width: max(x(segment.end) - x(segment.start), 3), height: height)
                        .offset(x: x(segment.start))
                }
                ForEach(row.feedTimes, id: \.self) { time in
                    Circle()
                        .fill(AppColor.accentFeed.opacity(row.isCurrent ? 1 : 0.7))
                        .overlay(Circle().strokeBorder(AppColor.card, lineWidth: 1.5))
                        .frame(width: height * 0.7, height: height * 0.7)
                        .offset(x: x(time) - height * 0.35)
                }
            }
            .frame(width: width, height: geo.size.height, alignment: .leading)
        }
        .frame(minHeight: 14)
    }

    /// Start, middle and end of the window, under the tracks.
    @ViewBuilder
    private var axis: some View {
        if let night = rows.last?.night {
            HStack(spacing: 8) {
                Color.clear.frame(width: labelWidth, height: 1)
                HStack {
                    Text(Self.hour(night.start))
                    Spacer()
                    Text(Self.hour(night.start.addingTimeInterval(night.duration / 2)))
                    Spacer()
                    Text(Self.hour(night.end))
                }
                .font(.caption2)
                .foregroundStyle(AppColor.text3)
                Color.clear.frame(width: totalWidth, height: 1)
            }
            .accessibilityHidden(true)
        }
    }

    private func accessibilityText(_ row: Row) -> String {
        let day = row.night.start.formatted(.dateTime.weekday(.wide))
        let slept = row.asleep > 0 ? "slept \(Self.duration(row.asleep))" : "no sleep logged"
        return "\(day) night, \(slept), \(Plural.count(row.feedTimes.count, "bottle"))"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        TimeFormatting.duration(minutes: Int((seconds / 60).rounded()))
    }

    /// "8p", "2a" — the axis has room for very little.
    private static func hour(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.defaultDigits(amPM: .narrow)))
    }
}

// MARK: - Bottles, by this time of day

/// Cumulative ounces through the day: today as a solid line to now, his
/// usual day dashed behind it. Fills the height it is given.
struct PaceChart: View {
    let pace: DayRhythm.Pace

    var body: some View {
        Chart {
            ForEach(pace.usual) { point in
                LineMark(x: .value("Hour", point.hour), y: .value("Ounces", point.oz),
                         series: .value("Day", "usual"))
                    .foregroundStyle(AppColor.text3)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    .interpolationMethod(.monotone)
            }
            ForEach(pace.today) { point in
                LineMark(x: .value("Hour", point.hour), y: .value("Ounces", point.oz),
                         series: .value("Day", "today"))
                    .foregroundStyle(AppColor.accentFeed)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let now = pace.today.last {
                PointMark(x: .value("Hour", now.hour), y: .value("Ounces", now.oz))
                    .foregroundStyle(AppColor.accentFeed)
                    .symbolSize(60)
            }
        }
        .chartXScale(domain: 0...24)
        .chartXAxis {
            AxisMarks(values: [0.0, 6, 12, 18, 24]) { value in
                AxisGridLine().foregroundStyle(AppColor.separator)
                AxisValueLabel {
                    if let hour = value.as(Double.self) {
                        Text(Self.label(hour))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(AppColor.separator)
                AxisValueLabel {
                    if let oz = value.as(Double.self) {
                        Text("\(Int(oz))")
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var text = "\(OzFormat.string(pace.ozSoFar.rounded())) ounces so far today"
        if let usual = pace.usualSoFar {
            text += ", usually \(OzFormat.string(usual.rounded())) by now"
        }
        return text
    }

    private static func label(_ hour: Double) -> String {
        switch Int(hour) {
        case 0, 24: return "12a"
        case 12: return "12p"
        case let h where h < 12: return "\(h)a"
        case let h: return "\(h - 12)p"
        }
    }
}

// MARK: - A number against his usual

/// One small figure — a label, today's value, and the usual beside it.
struct RhythmFigure: View {
    let label: String
    let value: String
    let usual: String?
    var tint: Color = AppColor.text

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).sectionLabelStyle()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(usual ?? " ")
                .font(.caption)
                .foregroundStyle(AppColor.text2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
