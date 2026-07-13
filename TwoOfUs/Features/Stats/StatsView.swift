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
    private var babyName: String { babies.first?.name ?? "Baby" }
    private var ageText: String? { babies.first.map { TimeFormatting.age(from: $0.dateOfBirth) } }
    private var hasAnyData: Bool { !feeds.isEmpty || !sleeps.isEmpty || !diapers.isEmpty }

    /// Show the Insights card only when it has something real to say: while a
    /// summary is generating, once one exists, or as a teaser before there's any
    /// data. When the model is available but generation yields nothing despite
    /// data (e.g. Simulator, or a transient failure), hide the card rather than
    /// showing the misleading "log a few feeds" empty-state over a week of data.
    private var showInsights: Bool {
        guard BabyIntelligence.isAvailable else { return false }
        return summaryLoading || summary != nil || !hasAnyData
    }

    @State private var summary: String?
    @State private var summaryLoading = false
    @State private var showWrapped = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if hasAnyData { wrappedButton }
                    if showInsights {
                        insightsCard
                    }
                    todayCard
                    recordHero
                    milestonesCard
                    lifetimeTiles
                    nightShiftCard
                    contributionCard
                    cadenceCard
                }
                .padding(16)
                // Kept on the always-present container (not on the conditionally
                // shown card) so generation still runs when the card is hidden.
                .task(id: "\(feeds.count)-\(sleeps.count)-\(diapers.count)") { await loadSummary() }
            }
            .background(AppColor.bg)
            .navigationTitle("Stats")
            .sheet(isPresented: $showWrapped) {
                WrappedShareView(engine: engine, babyName: babyName,
                                 ageText: ageText, babyPhoto: babies.first?.photoData)
            }
        }
    }

    // MARK: Wrapped (shareable weekly recap)

    private var wrappedButton: some View {
        Button { showWrapped = true } label: {
            HStack(spacing: 12) {
                Text("✨")
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(babyName)'s week")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Tap to share a recap")
                        .font(.caption)
                        .foregroundStyle(AppColor.nightlightCream.opacity(0.8))
                }
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.white)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [AppColor.indigoHi, AppColor.indigoLo],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share \(babyName)'s week")
    }

    // MARK: Insights (on-device AI)

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("INSIGHTS", systemImage: "sparkles")
                .sectionLabelStyle()
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
        .surfaceCard(cornerRadius: 18)
    }

    private func loadSummary() async {
        guard BabyIntelligence.isAvailable, !feeds.isEmpty else { return }
        // Debounce: the `.task(id:)` above cancels and restarts this on every
        // event change, so a widget batch of N events would otherwise regenerate
        // the summary N times. Wait out the burst first — a superseded run cancels
        // here before doing the expensive generation.
        try? await Task.sleep(for: .seconds(0.8))
        guard !Task.isCancelled else { return }
        summaryLoading = true
        defer { summaryLoading = false }
        summary = await BabyIntelligence.summary(digest: buildDigest(), babyName: babyName)
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
            // Fixed cream (not adaptive text2) — this card is always the dark indigo
            // gradient, so adaptive tokens go near-invisible in Light Mode. Matches
            // the sibling "…'s week" card's subtitle treatment.
            Text("🏆 Record — longest sleep")
                .sectionLabelStyle(color: AppColor.nightlightCream.opacity(0.75))
            if let record {
                Text(durationLong(record.duration))
                    .font(AppFont.display(38, weight: .heavy))
                    .foregroundStyle(.white)
                Text(Self.monthDay(record.date))
                    .font(.subheadline)
                    .foregroundStyle(AppColor.nightlightCream.opacity(0.8))
            } else {
                Text("—")
                    .font(AppFont.display(38, weight: .heavy))
                    .foregroundStyle(.white)
                Text("No completed sleeps yet")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.nightlightCream.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            LinearGradient(
                colors: [AppColor.indigoHi, AppColor.indigoLo],
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
                 unit: "≈ \(Plural.count(Int(sleepDays(t.totalSleepSeconds)) ?? 0, "day"))",
                 color: AppColor.accentSleep)
            tile(key: "💩 Diapers",
                 value: "\(t.diaperCount)",
                 unit: "since day one",
                 color: AppColor.accentDiaper)
            tile(key: "🍼 Bottles",
                 value: "\(t.feedCount)",
                 unit: "avg \(perDay(t.feedCount)) / day",
                 color: AppColor.accentFeed)
        }
    }

    private func tile(key: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(key).font(.caption).foregroundStyle(AppColor.text2)
            Text(value)
                .font(AppFont.display(28))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(unit).font(.caption2).foregroundStyle(AppColor.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surfaceCard(cornerRadius: 18)
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
                        Text("Night MVP this week: \(Text("\(mvp.name) 👑").font(.caption.weight(.bold)).foregroundStyle(AppColor.text))")
                            .font(.caption).foregroundStyle(AppColor.text3)
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
        Text("\(Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppColor.text)) — \(detail)")
            .font(.subheadline).foregroundStyle(AppColor.text2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Today vs typical

    private var todayCard: some View {
        let t = engine.todayVsTypical()
        let empty = t.feedsToday == 0 && t.diapersToday == 0 && t.sleepToday == 0
        return Card(title: "Today so far") {
            if empty {
                Text("Log today's first event to see how it's going.")
                    .font(.subheadline).foregroundStyle(AppColor.text3)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    todayRow("🍼", "\(Plural.count(t.feedsToday, "feed")) · \(OzFormat.string(t.ozToday.rounded())) oz",
                             t.hasHistory ? ozDelta(t.ozToday - t.ozAvg) : nil)
                    todayRow("💤", t.sleepToday > 0 ? durationLong(t.sleepToday) : "none yet",
                             t.hasHistory ? sleepDelta(t.sleepToday - t.sleepAvg) : nil)
                    todayRow("💩", Plural.count(t.diapersToday, "diaper"),
                             t.hasHistory ? countDelta(Double(t.diapersToday) - t.diapersAvg) : nil)
                }
            }
        }
    }

    private func todayRow(_ emoji: String, _ value: String, _ delta: String?) -> some View {
        HStack(spacing: 8) {
            Text(emoji)
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(AppColor.text)
            Spacer(minLength: 8)
            if let delta {
                Text(delta).font(.caption).foregroundStyle(AppColor.text3)
            }
        }
    }

    // MARK: Milestones

    private var milestonesCard: some View {
        let achieved = engine.milestones()
        let streak = engine.loggingStreak()
        let next = engine.nextMilestone()
        return Card(title: "Milestones") {
            if achieved.isEmpty && streak < 2 && next == nil {
                Text("Keep logging — moments like the first 5-hour sleep show up here.")
                    .font(.subheadline).foregroundStyle(AppColor.text3)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if streak >= 2 {
                        label("🔥 \(streak)-day logging streak", detail: "keep it going")
                    }
                    ForEach(achieved.prefix(3)) { m in
                        label("\(m.emoji) \(m.title)", detail: Self.monthDay(m.date))
                    }
                    if let next {
                        label("🎯 Next: \(next.title)", detail: "\(next.remaining) to go")
                    }
                }
            }
        }
    }

    // MARK: Teamwork (both-parents contribution)

    private var contributionCard: some View {
        let shares = engine.contributions()
        let total = shares.reduce(0) { $0 + $1.count }
        return Card(title: "🤝 Teamwork · all time") {
            if total == 0 {
                Text("Events you both log will split here.")
                    .font(.subheadline).foregroundStyle(AppColor.text3)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(shares) { s in
                                Rectangle()
                                    .fill(swatch(s.colorHex))
                                    .frame(width: geo.size.width * CGFloat(s.count) / CGFloat(total))
                            }
                        }
                    }
                    .frame(height: 14)
                    .clipShape(Capsule())

                    HStack {
                        ForEach(shares) { s in
                            HStack(spacing: 5) {
                                Circle().fill(swatch(s.colorHex)).frame(width: 8, height: 8)
                                Text("\(s.name) — \(s.count)")
                                    .font(.caption).foregroundStyle(AppColor.text2)
                            }
                            if s.id != shares.last?.id { Spacer() }
                        }
                    }
                    Text("\(total) events logged together")
                        .font(.caption).foregroundStyle(AppColor.text3)
                }
            }
        }
    }

    private func swatch(_ hex: String) -> Color {
        hex.isEmpty ? AppColor.accentFeed : Color(hex: hex)
    }

    /// "+3 oz vs avg" / "about average" for an ounce delta.
    private func ozDelta(_ diff: Double) -> String {
        let r = diff.rounded()
        if abs(r) < 1 { return "about average" }
        return "\(r > 0 ? "+" : "−")\(Int(abs(r))) oz vs avg"
    }

    /// Whole-count delta ("+2 vs avg").
    private func countDelta(_ diff: Double) -> String {
        let r = diff.rounded()
        if abs(r) < 1 { return "about average" }
        return "\(r > 0 ? "+" : "−")\(Int(abs(r))) vs avg"
    }

    /// Sleep delta in hours/minutes; within 15 min reads as "about average".
    private func sleepDelta(_ diffSeconds: Double) -> String {
        let mins = (diffSeconds / 60).rounded()
        if abs(mins) < 15 { return "about average" }
        let total = Int(abs(mins))
        let h = total / 60, m = total % 60
        let magnitude = h > 0 ? (m > 0 ? "\(h)h \(m)m" : "\(h)h") : "\(m)m"
        return "\(mins > 0 ? "+" : "−")\(magnitude) vs avg"
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
