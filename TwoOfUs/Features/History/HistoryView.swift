import SwiftUI
import SwiftData
import Charts

/// Trends over the last week: a day-in-the-life swimlane (reusing the ribbon),
/// the sleep-consolidation line, and daily formula volume. One column on every
/// iPhone; two columns that scroll together on iPhone Duo's inner display and
/// iPad (see `PaneLayout`).
struct HistoryView: View {
    @Query(filter: #Predicate<FeedEvent> { $0.deletedAt == nil }, sort: \FeedEvent.timestamp, order: .reverse)
    private var feeds: [FeedEvent]
    @Query(filter: #Predicate<SleepEvent> { $0.deletedAt == nil }, sort: \SleepEvent.startedAt, order: .reverse)
    private var sleeps: [SleepEvent]
    @Query(filter: #Predicate<DiaperEvent> { $0.deletedAt == nil }, sort: \DiaperEvent.timestamp, order: .reverse)
    private var diapers: [DiaperEvent]

    @Query private var babies: [Baby]

    private let days = 7

    private var engine: StatsEngine {
        StatsEngine(feeds: feeds, sleeps: sleeps, diapers: diapers)
    }

    private var babyName: String { babies.first?.name ?? "your baby" }
    private var hasAnyData: Bool { !feeds.isEmpty || !sleeps.isEmpty || !diapers.isEmpty }

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize

    var body: some View {
        NavigationStack {
            Group {
                if ScreenShape.isCompact(horizontal: hSize, vertical: vSize) {
                    content(split: nil)
                } else {
                    // Measured only off the compact path — a phone never
                    // builds this reader.
                    GeometryReader { proxy in
                        let layout = PaneLayout.resolve(in: proxy, horizontal: hSize)
                        switch layout.shape {
                        case .wide, .tall:
                            content(split: layout)
                        case .compact, .short:
                            // The outer display on its side: no fold, and one
                            // column of ~560 pt cards reads fine.
                            content(split: nil)
                        }
                    }
                }
            }
            .background(AppColor.bg)
            .navigationTitle("History")
        }
    }

    /// The tab's content: today's single column when `split` is nil (every
    /// iPhone, and the Duo's outer display either way up), or two columns
    /// along `split` (`.wide` / `.tall`: the Duo's inner display, iPad).
    @ViewBuilder
    private func content(split: PaneLayout?) -> some View {
        if hasAnyData {
            // The consolidation, total-sleep and volume cards all read the
            // same daily summaries; aggregate the history once per body and
            // pass it down rather than re-running the pass in each card (or
            // each column).
            let summaries = engine.dailySummaries(days: days)
            if let split {
                twoColumns(summaries, layout: split)
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        swimlaneCard()
                        consolidationCard(summaries)
                        sleepTotalCard(summaries)
                        volumeCard(summaries)
                        feedHeatmapCard()
                        diaperTrendCard()
                    }
                    .padding(16)
                }
            }
        } else if let split {
            // Top-aligned, not centred: centred, it would sit on the fold in
            // `.tall`. In `.wide` the fold runs down the middle instead, so the
            // message stays inside the leading pane rather than across it.
            VStack {
                noHistory
                Spacer()
            }
            .padding(.top, 48)
            .frame(width: split.shape == .wide ? split.leadingWidth : nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            // A single warm whole-screen empty state beats 7 blank
            // swimlane rows + five "No X yet" cards on first run.
            VStack {
                Spacer()
                noHistory
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var noHistory: some View {
        EmptyStateView(
            emoji: "📈",
            title: "No history yet",
            message: "Log a few feeds, sleeps, and diapers and \(babyName)'s trends will show up here."
        )
    }

    // MARK: Two columns (Duo inner display, iPad)

    /// `.wide` / `.tall`: the single column reflowed into two that scroll
    /// together — the day's rhythm leading, the daily totals trailing. In
    /// `.wide` the gap between them is the fold band. Each column holds three
    /// cards instead of six, so the charts get taller here.
    private func twoColumns(_ summaries: [DaySummary], layout: PaneLayout) -> some View {
        let columns = layout.columns
        return ScrollView {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 14) {
                    swimlaneCard(twoColumn: true)
                    consolidationCard(summaries, twoColumn: true)
                    feedHeatmapCard(twoColumn: true)
                }
                // Outer edge keeps the usual 16 pt; the inner edge only
                // `foldSideInset`, since the gap (the fold band in `.wide`)
                // already separates the columns.
                .padding(.leading, 16)
                .padding(.trailing, PaneLayout.foldSideInset)
                .frame(width: columns.leading)
                // VoiceOver finishes one column before starting the other.
                .accessibilityElement(children: .contain)

                Color.clear
                    .frame(width: columns.gap)
                    .accessibilityHidden(true)

                VStack(spacing: 14) {
                    sleepTotalCard(summaries, twoColumn: true)
                    volumeCard(summaries, twoColumn: true)
                    diaperTrendCard(twoColumn: true)
                }
                .padding(.leading, PaneLayout.foldSideInset)
                .padding(.trailing, 16)
                .frame(width: columns.trailing)
                .accessibilityElement(children: .contain)
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: Swimlane

    /// `twoColumn`: the taller ribbons (and roomier rows) of the two-column
    /// shapes; false is the phone's layout.
    private func swimlaneCard(twoColumn: Bool = false) -> some View {
        let rows = engine.swimlane(days: days)
        return Card(title: "Day in the life", trailing: "24h") {
            VStack(spacing: twoColumn ? 9 : 7) {
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        Text(Self.weekday(row.day))
                            .font(.caption2)
                            .foregroundStyle(AppColor.text3)
                            .frame(width: 28, alignment: .leading)
                        DayRibbonView(marks: row.marks, style: .color, day: row.day, showNowMarker: false)
                            .frame(height: twoColumn ? 24 : 16)
                    }
                    // The ribbon Canvas is hidden from accessibility — without
                    // this, VoiceOver reads seven bare weekday labels and no data.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Self.swimlaneSummary(row))
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

    private func consolidationCard(_ summaries: [DaySummary], twoColumn: Bool = false) -> some View {
        let best = summaries.map(\.longestStretch).max() ?? 0
        return Card(title: "Longest sleep stretch", trailing: durationShort(best)) {
            if best == 0 {
                emptyState("No completed sleeps yet", twoColumn: twoColumn)
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
                .chartXAxis { weekdayAxis(twoColumn: twoColumn) }
                .chartYAxis { softYAxis(unit: "h") }
                .frame(height: chartHeight(twoColumn: twoColumn))
            }
        }
    }

    // MARK: Daily volume

    private func volumeCard(_ summaries: [DaySummary], twoColumn: Bool = false) -> some View {
        let total = summaries.reduce(0.0) { $0 + $1.feedOz }
        // Average over days actually logged, not the whole window — pre-birth /
        // untracked zero-days would otherwise understate "avg" for a young baby.
        let trackedDays = summaries.filter { $0.feedOz > 0 }.count
        let avg = trackedDays == 0 ? 0 : total / Double(trackedDays)
        return Card(title: "Daily formula (oz)", trailing: "avg \(OzFormat.string(avg.rounded()))") {
            if total == 0 {
                emptyState("No feeds logged yet", twoColumn: twoColumn)
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
                .chartXAxis { weekdayAxis(twoColumn: twoColumn) }
                .chartYAxis { softYAxis(unit: "oz") }
                .frame(height: chartHeight(twoColumn: twoColumn))
            }
        }
    }

    // MARK: Total sleep per day

    private func sleepTotalCard(_ summaries: [DaySummary], twoColumn: Bool = false) -> some View {
        let total = summaries.reduce(0.0) { $0 + $1.sleepSeconds }
        // Average over days with sleep logged, not the whole window (see volumeCard).
        let trackedDays = summaries.filter { $0.sleepSeconds > 0 }.count
        let avgPerDay = trackedDays == 0 ? 0 : total / Double(trackedDays)
        return Card(title: "Total sleep per day", trailing: "avg \(durationShort(avgPerDay))") {
            if total == 0 {
                emptyState("No completed sleeps yet", twoColumn: twoColumn)
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
                .chartXAxis { weekdayAxis(twoColumn: twoColumn) }
                .chartYAxis { softYAxis(unit: "h") }
                .frame(height: chartHeight(twoColumn: twoColumn))
            }
        }
    }

    // MARK: Feeding times (day × hour heatmap)

    private func feedHeatmapCard(twoColumn: Bool = false) -> some View {
        let cells = engine.feedHeatmap(days: days)
        let peak = cells.map(\.count).max() ?? 0
        // Oldest → newest weekday labels, indexed to match each cell's dayIndex.
        let labels: [String] = (0..<days).compactMap { idx in
            cells.first { $0.dayIndex == idx }.map { Self.weekday($0.day) }
        }
        return Card(title: "Feeding times", trailing: "by hour") {
            if peak == 0 {
                emptyState("No feeds logged yet", twoColumn: twoColumn)
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
                .frame(height: twoColumn ? 168 : 132)
            }
        }
    }

    // MARK: Diaper trend (wet / dirty / both)

    private func diaperTrendCard(twoColumn: Bool = false) -> some View {
        let trend = engine.diaperDays(days: days)
        let total = trend.reduce(0) { $0 + $1.total }
        return Card(title: "Diapers per day") {
            if total == 0 {
                emptyState("No diapers logged yet", twoColumn: twoColumn)
            } else {
                VStack(spacing: 10) {
                    Chart {
                        ForEach(trend) { d in
                            BarMark(x: .value("Day", d.day, unit: .day),
                                    y: .value("Count", Double(d.wet)), width: .ratio(0.58))
                                .foregroundStyle(by: .value("Type", "Wet"))
                                .cornerRadius(3)
                            BarMark(x: .value("Day", d.day, unit: .day),
                                    y: .value("Count", Double(d.dirty)), width: .ratio(0.58))
                                .foregroundStyle(by: .value("Type", "Dirty"))
                                .cornerRadius(3)
                            BarMark(x: .value("Day", d.day, unit: .day),
                                    y: .value("Count", Double(d.both)), width: .ratio(0.58))
                                .foregroundStyle(by: .value("Type", "Both"))
                                .cornerRadius(3)
                        }
                    }
                    .chartForegroundStyleScale([
                        "Wet": AppColor.accentDiaper.opacity(0.45),
                        "Dirty": AppColor.accentDiaper.opacity(0.72),
                        "Both": AppColor.accentDiaper,
                    ])
                    .chartXAxis { weekdayAxis(twoColumn: twoColumn) }
                    .chartYAxis { softYAxis(unit: "") }
                    .chartLegend(.hidden)
                    .frame(height: chartHeight(twoColumn: twoColumn))

                    HStack(spacing: 16) {
                        legendBar(AppColor.accentDiaper.opacity(0.45), label: "wet")
                        legendBar(AppColor.accentDiaper.opacity(0.72), label: "dirty")
                        legendBar(AppColor.accentDiaper, label: "both")
                    }
                }
            }
        }
    }

    /// Compact hour label for the heatmap axis (0/6/12/18/24 → 12a/6a/12p/6p/12a),
    /// or the plain hour number for 24-hour locales (→ 0/6/12/18/0).
    private static func hourShort(_ hour: Int) -> String {
        let h = hour % 24
        switch Locale.current.hourCycle {
        case .zeroToTwentyThree, .oneToTwentyFour:
            return "\(h)"
        default:
            let suffix = h < 12 ? "a" : "p"
            let twelve = h % 12 == 0 ? 12 : h % 12
            return "\(twelve)\(suffix)"
        }
    }

    // MARK: Helpers

    /// Height of the bar / line charts: the phone's 120 pt, or 150 pt in the
    /// two-column shapes (three cards per column instead of six).
    private func chartHeight(twoColumn: Bool) -> CGFloat {
        twoColumn ? 150 : 120
    }

    /// `twoColumn` labels the days "Mon", "Tue"… where the phone has room only
    /// for "M", "T"….
    private func weekdayAxis(twoColumn: Bool = false) -> some AxisContent {
        AxisMarks(values: .stride(by: .day)) { _ in
            AxisGridLine().foregroundStyle(AppColor.separator.opacity(0.35))
            AxisValueLabel(format: .dateTime.weekday(twoColumn ? .abbreviated : .narrow))
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

    /// Centred on a phone; leading-aligned (in line with the card's title) in
    /// the two-column shapes.
    private func emptyState(_ text: String, twoColumn: Bool = false) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(AppColor.text3)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: twoColumn ? .leading : .center)
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
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    /// Spoken summary of one swimlane row, e.g.
    /// "Tuesday: 6 feeds, 3 hours 20 minutes of sleep, 4 diapers."
    private static func swimlaneSummary(_ row: DayMarks) -> String {
        let feeds = row.marks.filter { $0.kind == .feed }.count
        let diapers = row.marks.filter { $0.kind == .diaper }.count
        let sleepSeconds = row.marks
            .filter { $0.kind == .sleep }
            .reduce(0.0) { $0 + (($1.end ?? $1.start).timeIntervalSince($1.start)) }
        let mins = Int(sleepSeconds / 60)
        let sleep: String
        if mins == 0 {
            sleep = "no sleep logged"
        } else {
            let h = mins / 60, m = mins % 60
            let hours = h == 1 ? "1 hour" : "\(h) hours"
            let minutes = m == 1 ? "1 minute" : "\(m) minutes"
            let span = h == 0 ? minutes : (m == 0 ? hours : "\(hours) \(minutes)")
            sleep = "\(span) of sleep"
        }
        let day = row.day.formatted(.dateTime.weekday(.wide))
        return "\(day): \(Plural.count(feeds, "feed")), \(sleep), \(Plural.count(diapers, "diaper"))."
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
