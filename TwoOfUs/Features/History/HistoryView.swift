import SwiftUI
import SwiftData
import Charts

/// Trends over the last week: a day-in-the-life swimlane (reusing the ribbon),
/// the sleep-consolidation line, and daily formula volume.
struct HistoryView: View {
    @Query(filter: #Predicate<FeedEvent> { $0.deletedAt == nil }, sort: \FeedEvent.timestamp, order: .reverse)
    private var feeds: [FeedEvent]
    @Query(filter: #Predicate<SleepEvent> { $0.deletedAt == nil }, sort: \SleepEvent.startedAt, order: .reverse)
    private var sleeps: [SleepEvent]
    @Query(filter: #Predicate<DiaperEvent> { $0.deletedAt == nil }, sort: \DiaperEvent.timestamp, order: .reverse)
    private var diapers: [DiaperEvent]

    private let days = 7

    private var engine: StatsEngine {
        StatsEngine(feeds: feeds, sleeps: sleeps, diapers: diapers)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    swimlaneCard
                    consolidationCard
                    sleepTotalCard
                    volumeCard
                    feedHeatmapCard
                    diaperTrendCard
                }
                .padding(16)
            }
            .background(AppColor.bg)
            .navigationTitle("History")
        }
    }

    // MARK: Swimlane

    private var swimlaneCard: some View {
        let rows = engine.swimlane(days: days)
        return Card(title: "Day in the life", trailing: "24h") {
            VStack(spacing: 7) {
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        Text(Self.weekday(row.day))
                            .font(.caption2)
                            .foregroundStyle(AppColor.text3)
                            .frame(width: 28, alignment: .leading)
                        DayRibbonView(marks: row.marks, style: .color, day: row.day, showNowMarker: false)
                            .frame(height: 16)
                    }
                }
                HStack(spacing: 16) {
                    legendEmoji("🍼", label: "feed")
                    legendBar(AppColor.accentSleep, label: "sleep")
                    legendEmoji("💧💩", label: "diaper")
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: Sleep consolidation

    private var consolidationCard: some View {
        let summaries = engine.dailySummaries(days: days)
        let best = summaries.map(\.longestStretch).max() ?? 0
        return Card(title: "Longest sleep stretch", trailing: durationShort(best)) {
            if best == 0 {
                emptyState("No completed sleeps yet")
            } else {
                Chart(summaries) { s in
                    let hours = s.longestStretch / 3600
                    AreaMark(
                        x: .value("Day", s.day, unit: .day),
                        y: .value("Hours", hours)
                    )
                    .foregroundStyle(.linearGradient(
                        colors: [AppColor.accentSleep.opacity(0.35), AppColor.accentSleep.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Day", s.day, unit: .day),
                        y: .value("Hours", hours)
                    )
                    .foregroundStyle(AppColor.accentSleep)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Day", s.day, unit: .day),
                        y: .value("Hours", hours)
                    )
                    .foregroundStyle(AppColor.accentSleep)
                    .symbolSize(28)
                }
                .chartXAxis { weekdayAxis() }
                .chartYAxis { softYAxis(unit: "h") }
                .frame(height: 120)
            }
        }
    }

    // MARK: Daily volume

    private var volumeCard: some View {
        let summaries = engine.dailySummaries(days: days)
        let total = summaries.reduce(0.0) { $0 + $1.feedOz }
        let avg = summaries.isEmpty ? 0 : total / Double(summaries.count)
        return Card(title: "Daily formula (oz)", trailing: "avg \(OzFormat.string(avg.rounded()))") {
            if total == 0 {
                emptyState("No feeds logged yet")
            } else {
                Chart(summaries) { s in
                    BarMark(
                        x: .value("Day", s.day, unit: .day),
                        y: .value("Ounces", s.feedOz),
                        width: .ratio(0.58)
                    )
                    .foregroundStyle(.linearGradient(
                        colors: [AppColor.accentFeed, AppColor.accentFeed.opacity(0.45)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .cornerRadius(6)

                    if avg > 0 {
                        RuleMark(y: .value("Average", avg))
                            .foregroundStyle(AppColor.text3.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartXAxis { weekdayAxis() }
                .chartYAxis { softYAxis(unit: "oz") }
                .frame(height: 120)
            }
        }
    }

    // MARK: Total sleep per day

    private var sleepTotalCard: some View {
        let summaries = engine.dailySummaries(days: days)
        let total = summaries.reduce(0.0) { $0 + $1.sleepSeconds }
        let avgPerDay = summaries.isEmpty ? 0 : total / Double(summaries.count)
        return Card(title: "Total sleep per day", trailing: "avg \(durationShort(avgPerDay))") {
            if total == 0 {
                emptyState("No completed sleeps yet")
            } else {
                Chart(summaries) { s in
                    BarMark(
                        x: .value("Day", s.day, unit: .day),
                        y: .value("Hours", s.sleepSeconds / 3600),
                        width: .ratio(0.58)
                    )
                    .foregroundStyle(.linearGradient(
                        colors: [AppColor.accentSleep, AppColor.accentSleep.opacity(0.45)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .cornerRadius(6)

                    if avgPerDay > 0 {
                        RuleMark(y: .value("Average", avgPerDay / 3600))
                            .foregroundStyle(AppColor.text3.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartXAxis { weekdayAxis() }
                .chartYAxis { softYAxis(unit: "h") }
                .frame(height: 120)
            }
        }
    }

    // MARK: Feeding times (day × hour heatmap)

    private var feedHeatmapCard: some View {
        let cells = engine.feedHeatmap(days: days)
        let peak = cells.map(\.count).max() ?? 0
        // Oldest → newest weekday labels, indexed to match each cell's dayIndex.
        let labels: [String] = (0..<days).compactMap { idx in
            cells.first { $0.dayIndex == idx }.map { Self.weekday($0.day) }
        }
        return Card(title: "Feeding times", trailing: "by hour") {
            if peak == 0 {
                emptyState("No feeds logged yet")
            } else {
                Chart(cells) { c in
                    RectangleMark(
                        xStart: .value("Hour", c.hour),
                        xEnd: .value("Hour", c.hour + 1),
                        yStart: .value("Day", Double(c.dayIndex)),
                        yEnd: .value("Day", Double(c.dayIndex + 1))
                    )
                    // Opacity ramps with how many feeds fell in that hour; empty
                    // cells stay barely-there so the busy hours read at a glance.
                    .foregroundStyle(AppColor.accentFeed.opacity(
                        c.count == 0 ? 0.05 : 0.25 + 0.75 * Double(c.count) / Double(peak)
                    ))
                }
                .chartXScale(domain: 0...24)
                .chartYScale(domain: 0...Double(labels.count))
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18, 24]) { value in
                        AxisGridLine().foregroundStyle(AppColor.separator.opacity(0.25))
                        AxisValueLabel {
                            if let h = value.as(Int.self) {
                                Text(Self.hourShort(h)).font(.caption2).foregroundStyle(AppColor.text3)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: labels.indices.map { Double($0) + 0.5 }) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self), Int(v) < labels.count {
                                Text(labels[Int(v)]).font(.caption2).foregroundStyle(AppColor.text3)
                            }
                        }
                    }
                }
                .frame(height: 132)
            }
        }
    }

    // MARK: Diaper trend (wet / dirty / both)

    private var diaperTrendCard: some View {
        let trend = engine.diaperDays(days: days)
        let total = trend.reduce(0) { $0 + $1.total }
        return Card(title: "Diapers per day") {
            if total == 0 {
                emptyState("No diapers logged yet")
            } else {
                VStack(spacing: 10) {
                    Chart {
                        ForEach(trend) { d in
                            ForEach(Self.diaperSegments, id: \.label) { seg in
                                BarMark(
                                    x: .value("Day", d.day, unit: .day),
                                    y: .value("Count", Double(seg.count(d))),
                                    width: .ratio(0.58)
                                )
                                .foregroundStyle(by: .value("Type", seg.label))
                                .cornerRadius(3)
                            }
                        }
                    }
                    .chartForegroundStyleScale(Self.diaperColorScale)
                    .chartXAxis { weekdayAxis() }
                    .chartYAxis { softYAxis(unit: "") }
                    .chartLegend(.hidden)
                    .frame(height: 120)

                    HStack(spacing: 16) {
                        ForEach(Self.diaperSegments, id: \.label) { seg in
                            legendBar(seg.color, label: seg.label.lowercased())
                        }
                    }
                }
            }
        }
    }

    /// The three diaper segments, in stack order (wet → dirty → both), each with a
    /// shade of the diaper accent so the card stays monochrome-amber per §2.
    private static let diaperSegments: [(label: String, color: Color, count: (DiaperDay) -> Int)] = [
        ("Wet",   AppColor.accentDiaper.opacity(0.45), { $0.wet }),
        ("Dirty", AppColor.accentDiaper.opacity(0.72), { $0.dirty }),
        ("Both",  AppColor.accentDiaper,               { $0.both }),
    ]

    private static var diaperColorScale: KeyValuePairs<String, Color> {
        ["Wet": AppColor.accentDiaper.opacity(0.45),
         "Dirty": AppColor.accentDiaper.opacity(0.72),
         "Both": AppColor.accentDiaper]
    }

    /// Compact hour label for the heatmap axis (0/6/12/18/24 → 12a/6a/12p/6p/12a).
    private static func hourShort(_ hour: Int) -> String {
        let h = hour % 24
        let suffix = h < 12 ? "a" : "p"
        let twelve = h % 12 == 0 ? 12 : h % 12
        return "\(twelve)\(suffix)"
    }

    // MARK: Helpers

    private func weekdayAxis() -> some AxisContent {
        AxisMarks(values: .stride(by: .day)) { _ in
            AxisGridLine().foregroundStyle(AppColor.separator.opacity(0.35))
            AxisValueLabel(format: .dateTime.weekday(.narrow))
                .font(.caption2)
                .foregroundStyle(AppColor.text3)
        }
    }

    /// A quiet y-axis: a few soft gridlines with compact, unit-suffixed labels.
    private func softYAxis(unit: String) -> some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
            AxisGridLine().foregroundStyle(AppColor.separator.opacity(0.3))
            AxisValueLabel {
                if let n = value.as(Double.self) {
                    Text("\(Int(n))\(unit)")
                        .font(.caption2)
                        .foregroundStyle(AppColor.text3)
                }
            }
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(AppColor.text3)
            .frame(maxWidth: .infinity, minHeight: 80)
    }

    private func legendBar(_ color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 4)
            Text(label).font(.caption2).foregroundStyle(AppColor.text2)
        }
    }

    private func legendEmoji(_ emoji: String, label: String) -> some View {
        HStack(spacing: 5) {
            Text(emoji).font(.system(size: 9))
            Text(label).font(.caption2).foregroundStyle(AppColor.text2)
        }
    }

    private func durationShort(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "—" }
        return TimeFormatting.duration(from: .now, to: .now.addingTimeInterval(seconds))
    }

    private static func weekday(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }
}

/// Simple titled card container used across the data tabs.
struct Card<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .sectionLabelStyle()
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.caption)
                        .foregroundStyle(AppColor.text3)
                }
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(cornerRadius: 18)
    }
}

#Preview {
    HistoryView()
        .modelContainer(AppModelContainer.preview)
        .preferredColorScheme(.dark)
}
