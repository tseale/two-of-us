import SwiftUI
import SwiftData

/// The delightful layer: records, lifetime counters in fun units, the night-shift
/// split, hungriest hour, and a "since a week ago" cadence note.
struct StatsView: View {
    @Query private var babies: [Baby]
    @Query(filter: #Predicate<FeedEvent> { $0.deletedAt == nil })
    private var feeds: [FeedEvent]
    @Query(filter: #Predicate<SleepEvent> { $0.deletedAt == nil })
    private var sleeps: [SleepEvent]
    @Query(filter: #Predicate<DiaperEvent> { $0.deletedAt == nil })
    private var diapers: [DiaperEvent]

    private var engine: StatsEngine {
        StatsEngine(feeds: feeds, sleeps: sleeps, diapers: diapers)
    }
    private var babyName: String { babies.first?.name ?? "Miller" }

    @State private var summary: String?
    @State private var summaryLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if MillerIntelligence.isAvailable {
                        insightsCard
                    }
                    recordHero
                    lifetimeTiles
                    nightShiftCard
                    cadenceCard
                }
                .padding(16)
            }
            .background(AppColor.bg)
            .navigationTitle("Stats")
        }
    }

    // MARK: Insights (on-device AI)

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("INSIGHTS", systemImage: "sparkles")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppColor.text2)
            if let summary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.text)
            } else if summaryLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Reading the last week…")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.text2)
                }
            } else {
                Text("Log a few feeds and sleeps to see patterns here.")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.text2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 18)
        .task(id: feeds.count) { await loadSummary() }
    }

    private func loadSummary() async {
        guard MillerIntelligence.isAvailable, !feeds.isEmpty else { return }
        summaryLoading = true
        defer { summaryLoading = false }
        summary = await MillerIntelligence.summary(digest: buildDigest(), babyName: babyName)
    }

    /// Compact, model-friendly digest of the last week's numbers.
    private func buildDigest() -> String {
        let t = engine.lifetime()
        let days = engine.dailySummaries(days: 7)
        var lines = ["Baby: \(babyName)"]
        lines.append("Lifetime: \(Int(t.totalOz.rounded())) oz over \(t.feedCount) feeds, "
                     + "\(t.diaperCount) diapers, \(Int((t.totalSleepSeconds / 3600).rounded()))h sleep.")
        if let r = engine.longestSleep() {
            lines.append("Longest sleep: \(Int(r.duration / 3600))h \(Int(r.duration.truncatingRemainder(dividingBy: 3600) / 60))m.")
        }
        if let hour = engine.hungriestHour() { lines.append("Busiest feeding hour: \(hour):00.") }
        if let avg = engine.averageFeedInterval(fromDaysAgo: 3, toDaysAgo: 0) {
            lines.append("Recent avg gap between feeds: \(Int(avg / 3600))h \(Int(avg.truncatingRemainder(dividingBy: 3600) / 60))m.")
        }
        lines.append("Last 7 days (day: oz / feeds / sleep h / diapers):")
        for d in days {
            lines.append("  \(Self.monthDay(d.day)): \(Int(d.feedOz.rounded()))oz / \(d.feedCount) / "
                         + "\(String(format: "%.1f", d.sleepSeconds / 3600))h / \(d.diaperCount)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Record hero

    private var recordHero: some View {
        let record = engine.longestSleep()
        return VStack(alignment: .leading, spacing: 6) {
            Text("🏆 RECORD — LONGEST SLEEP")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppColor.text2)
            if let record {
                Text(durationLong(record.duration))
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(AppColor.text)
                Text(Self.monthDay(record.date))
                    .font(.subheadline)
                    .foregroundStyle(AppColor.text2)
            } else {
                Text("—")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(AppColor.text)
                Text("No completed sleeps yet")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.text2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(hex: "2A2A4D"), Color(hex: "1C1C2E")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
    }

    // MARK: Lifetime tiles

    private var lifetimeTiles: some View {
        let t = engine.lifetime()
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            tile(key: "🥛 Total milk",
                 value: "\(OzFormat.string(t.totalOz.rounded())) oz",
                 unit: "≈ \(gallons(t.totalOz)) gallons",
                 color: AppColor.accentFeed)
            tile(key: "💤 Total sleep",
                 value: "\(Int((t.totalSleepSeconds / 3600).rounded()))h",
                 unit: "≈ \(sleepDays(t.totalSleepSeconds)) days",
                 color: AppColor.accentSleep)
            tile(key: "💩 Diapers",
                 value: "\(t.diaperCount)",
                 unit: "since day one",
                 color: AppColor.accentDiaper)
            tile(key: "🍼 Bottles",
                 value: "\(t.feedCount)",
                 unit: "avg \(perDay(t.feedCount)) / day",
                 color: AppColor.text)
        }
    }

    private func tile(key: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(key).font(.caption).foregroundStyle(AppColor.text2)
            Text(value).font(.title.weight(.bold)).foregroundStyle(color)
            Text(unit).font(.caption2).foregroundStyle(AppColor.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(cornerRadius: 18)
    }

    // MARK: Night shift

    private var nightShiftCard: some View {
        let shares = engine.nightShift(days: 7)
        let total = shares.reduce(0) { $0 + $1.count }
        return Card(title: "🌙 Night shift · this week") {
            if total == 0 {
                Text("No night feeds logged this week")
                    .font(.subheadline).foregroundStyle(AppColor.text3)
                    .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(shares) { share in
                                Rectangle()
                                    .fill(shareColor(share))
                                    .frame(width: geo.size.width * CGFloat(share.count) / CGFloat(total))
                            }
                        }
                    }
                    .frame(height: 14)
                    .clipShape(Capsule())

                    HStack {
                        ForEach(shares) { share in
                            HStack(spacing: 5) {
                                Circle().fill(shareColor(share)).frame(width: 8, height: 8)
                                Text("\(share.name) — \(share.count)")
                                    .font(.caption).foregroundStyle(AppColor.text2)
                            }
                            if share.id != shares.last?.id { Spacer() }
                        }
                    }
                    if let mvp = shares.first {
                        Text("Night MVP this week: ")
                            .font(.caption).foregroundStyle(AppColor.text3)
                        + Text("\(mvp.name) 👑").font(.caption.weight(.bold)).foregroundStyle(AppColor.text)
                    }
                }
            }
        }
    }

    // MARK: Cadence

    private var cadenceCard: some View {
        Card(title: "Patterns") {
            VStack(alignment: .leading, spacing: 12) {
                if let hour = engine.hungriestHour() {
                    label("🕕 Hungriest hour", detail: "around \(Self.hourLabel(hour))")
                }
                if let note = cadenceNote {
                    label("📅 On this day", detail: note)
                }
                if engine.hungriestHour() == nil && cadenceNote == nil {
                    Text("Log a few more feeds to unlock patterns")
                        .font(.subheadline).foregroundStyle(AppColor.text3)
                }
            }
        }
    }

    private var cadenceNote: String? {
        guard
            let recent = engine.averageFeedInterval(fromDaysAgo: 3, toDaysAgo: 0),
            let prior = engine.averageFeedInterval(fromDaysAgo: 10, toDaysAgo: 7)
        else { return nil }
        let now = intervalLabel(recent)
        let then = intervalLabel(prior)
        if now == then { return "Feeding about every \(now), steady as last week." }
        return "A week ago, every \(then). Now every \(now)."
    }

    private func label(_ title: String, detail: String) -> some View {
        (Text(title + " ").font(.subheadline.weight(.semibold)).foregroundStyle(AppColor.text)
         + Text("— " + detail).font(.subheadline).foregroundStyle(AppColor.text2))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Formatting

    private func shareColor(_ share: CaregiverShare) -> Color {
        share.colorHex.isEmpty ? AppColor.accentFeed : Color(hex: share.colorHex)
    }
    private func gallons(_ oz: Double) -> String { String(format: "%.1f", oz / 128) }
    private func sleepDays(_ seconds: TimeInterval) -> String { String(format: "%.0f", seconds / 86_400) }
    private func perDay(_ count: Int) -> String {
        guard let dob = babies.first?.dateOfBirth else { return "—" }
        let days = max(1, Calendar.current.dateComponents([.day], from: dob, to: .now).day ?? 1)
        return String(format: "%.1f", Double(count) / Double(days))
    }
    private func durationLong(_ seconds: TimeInterval) -> String {
        TimeFormatting.duration(from: .now, to: .now.addingTimeInterval(seconds))
    }
    private func intervalLabel(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
    private static func monthDay(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: date)
    }
    private static func hourLabel(_ hour: Int) -> String {
        var c = DateComponents(); c.hour = hour
        let date = Calendar.current.date(from: c) ?? .now
        let f = DateFormatter(); f.dateFormat = "h a"; return f.string(from: date)
    }
}

#Preview {
    StatsView()
        .modelContainer(AppModelContainer.preview)
        .preferredColorScheme(.dark)
}
