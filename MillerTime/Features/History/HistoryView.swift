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
                    volumeCard
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
                    legend(color: AppColor.accentFeed, label: "feed", isBar: false)
                    legend(color: AppColor.accentSleep, label: "sleep", isBar: true)
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
                    LineMark(
                        x: .value("Day", s.day, unit: .day),
                        y: .value("Hours", s.longestStretch / 3600)
                    )
                    .foregroundStyle(AppColor.accentSleep)
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("Day", s.day, unit: .day),
                        y: .value("Hours", s.longestStretch / 3600)
                    )
                    .foregroundStyle(AppColor.accentSleep)
                }
                .chartXAxis { weekdayAxis() }
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
                        y: .value("Ounces", s.feedOz)
                    )
                    .foregroundStyle(AppColor.accentFeed)
                    .cornerRadius(4)
                }
                .chartXAxis { weekdayAxis() }
                .frame(height: 120)
            }
        }
    }

    // MARK: Helpers

    private func weekdayAxis() -> some AxisContent {
        AxisMarks(values: .stride(by: .day)) { value in
            AxisValueLabel(format: .dateTime.weekday(.narrow))
            AxisGridLine()
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(AppColor.text3)
            .frame(maxWidth: .infinity, minHeight: 80)
    }

    private func legend(color: Color, label: String, isBar: Bool) -> some View {
        HStack(spacing: 5) {
            if isBar {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 4)
            } else {
                Circle().fill(color).frame(width: 8, height: 8)
            }
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.text2)
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
        .background(AppColor.card, in: RoundedRectangle(cornerRadius: 18))
    }
}

#Preview {
    HistoryView()
        .modelContainer(AppModelContainer.preview)
        .preferredColorScheme(.dark)
}
