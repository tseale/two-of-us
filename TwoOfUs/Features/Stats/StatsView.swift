import SwiftUI
import UIKit
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
    @Query private var settingsList: [SharedSettings]

    /// The family-wide AI switch (Settings → Feeding & Tracking). Governs the
    /// insights card the same way it governs the prediction hints.
    private var aiEnabled: Bool {
        SharedSettings.canonical(settingsList)?.aiPredictionsEnabled ?? true
    }

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
        guard aiEnabled, BabyIntelligence.isAvailable else { return false }
        return summaryLoading || summary != nil || !hasAnyData
    }

    @State private var summary: String?
    @State private var summaryLoading = false
    @State private var outlookRows: [TodayOutlook.Row] = []
    @State private var patterns: BabyIntelligence.WeeklyPatterns?
    @State private var timeAccuracy: AccuracyReport?
    @State private var amountAccuracy: AccuracyReport?
    @State private var sleepAccuracy: AccuracyReport?
    @State private var showWrapped = false
    @State private var showCareSummary = false

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize

    /// The phone idiom. With a `.wide` layout that is only ever iPhone Duo
    /// open in landscape: slab iPhones are always compact, and an iPad (which
    /// resolves `.wide` too) keeps its two columns exactly. Never a
    /// device-model check.
    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    var body: some View {
        NavigationStack {
            // A ZStack, not a Group: a Group hands its modifiers to whichever
            // branch is showing, so the task below would restart and an open
            // sheet be torn down whenever the phone opens or closes. The
            // ZStack keeps one identity across both layouts.
            ZStack {
                if ScreenShape.isCompact(horizontal: hSize, vertical: vSize) {
                    singleColumn
                } else {
                    // Measured only off the compact path — a phone never
                    // builds this reader.
                    GeometryReader { proxy in
                        let layout = PaneLayout.resolve(in: proxy, horizontal: hSize)
                        switch layout.shape {
                        case .wide:
                            // A grid only ever resolves for the phone idiom —
                            // iPhone Duo's inner display. iPad (and a reader
                            // too narrow for two pages) keeps the two columns
                            // exactly as they were.
                            if let grid = SpreadGrid(layout: layout, isPhone: isPhone) {
                                spread(layout, grid: grid)
                            } else {
                                twoColumns(layout)
                            }
                        case .tall:
                            twoColumns(layout)
                        case .compact, .short:
                            // The outer display on its side: no fold, and one
                            // column of ~560 pt cards reads fine.
                            singleColumn
                        }
                    }
                }
            }
            // Kept on the always-present container (not on the conditionally
            // shown card, nor on either layout) so generation still runs when
            // the card is hidden, and isn't restarted by opening or closing
            // the phone.
            .task(id: "\(feeds.count)-\(sleeps.count)-\(diapers.count)") { await loadSummary() }
            .background(AppColor.bg)
            .navigationTitle("Stats")
            .sheet(isPresented: $showWrapped) {
                WrappedShareView(engine: engine, babyName: babyName,
                                 ageText: ageText, babyPhoto: babies.first?.photoData)
            }
            .sheet(isPresented: $showCareSummary) {
                CareSummarySheet(babyName: babyName,
                                 dateOfBirth: babies.first?.dateOfBirth, engine: engine)
            }
        }
    }

    // MARK: Layouts

    /// Today's single column: every iPhone, and the Duo's outer display
    /// either way up.
    private var singleColumn: some View {
        ScrollView {
            VStack(spacing: 14) {
                wrappedButtonIfShown
                insightsCardIfShown()
                outlookCardIfShown()
                patternsCardIfShown()
                todayCard
                recordHero()
                milestonesCard
                lifetimeTiles
                nightShiftCard()
                contributionCard
                cadenceCard
                accuracyCardIfShown
                careSummaryButtonIfShown
            }
            .padding(16)
        }
    }

    /// `.tall` (the Duo open in portrait) and `.wide` on iPad: the single
    /// column reflowed into two that scroll together — the glance (records,
    /// totals, today) leading, this week and the AI cards trailing. In
    /// `.wide` the gap between them is the fold band. (The Duo open in
    /// landscape has the spread instead.)
    private func twoColumns(_ layout: PaneLayout) -> some View {
        let columns = layout.columns
        return ScrollView {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 14) {
                    wrappedButtonIfShown
                    recordHero()
                    lifetimeTiles
                    todayCard
                    milestonesCard
                    careSummaryButtonIfShown
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
                    insightsCardIfShown()
                    outlookCardIfShown()
                    patternsCardIfShown()
                    nightShiftCard(twoColumn: true)
                    contributionCard
                    cadenceCard
                    accuracyCardIfShown
                }
                .padding(.leading, PaneLayout.foldSideInset)
                .padding(.trailing, 16)
                .frame(width: columns.trailing)
                .accessibilityElement(children: .contain)
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: The spread (iPhone Duo open in landscape, flat or like a book)

    /// Stats on iPhone Duo's open display in landscape: the two pages Home
    /// opens on (`SpreadScaffold` draws the light, the avatar and the
    /// titles), holding the two columns' own split — the glance on the
    /// leading page, this week and what's next on the trailing one. Each
    /// page scrolls on its own under a title that stays put.
    ///
    /// A page opens on a first screen that ends exactly on the foot line, as
    /// Home's pages do. Leading: the share row and the lifetime tiles at
    /// their natural heights, with the record between them taking the slack
    /// — its numerals stay where they are and the card gets taller. Trailing:
    /// the AI cards that are showing, the last of them taking the slack;
    /// with none showing there is no first screen to fill and the page
    /// simply starts with the night shift. Everything else is a scroll away,
    /// and at a text size where a first screen needs more than its page,
    /// nothing stretches and the page scrolls sooner.
    private func spread(_ layout: PaneLayout, grid: SpreadGrid) -> some View {
        let lastLead = lastLeadCard
        return SpreadScaffold(
            layout: layout, grid: grid, baby: babies.first,
            leading: SpreadPage("Stats", subtitle: "All time") { height in
                SpreadPageScroll {
                    SpreadFirstScreen(height: height) {
                        // Natural height, whatever the page offers: a stack
                        // sharing out a fixed height can otherwise hand a
                        // card less than its text needs.
                        wrappedButtonIfShown
                            .fixedSize(horizontal: false, vertical: true)
                        recordHero(fillsPage: true)
                        lifetimeTiles
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    todayCard
                    milestonesCard
                    careSummaryButtonIfShown
                }
            },
            trailing: SpreadPage("This week", subtitle: "and what's next") { height in
                SpreadPageScroll {
                    if let lastLead {
                        SpreadFirstScreen(height: height) {
                            // Each at its natural height but the last one
                            // showing, which is left free to grow.
                            insightsCardIfShown(fillsPage: lastLead == .insights)
                                .fixedSize(horizontal: false, vertical: lastLead != .insights)
                            outlookCardIfShown(fillsPage: lastLead == .outlook)
                                .fixedSize(horizontal: false, vertical: lastLead != .outlook)
                            patternsCardIfShown(fillsPage: lastLead == .patterns)
                        }
                    }
                    nightShiftCard(twoColumn: true)
                    contributionCard
                    cadenceCard
                    accuracyCardIfShown
                }
            })
    }

    // MARK: Conditionally shown cards
    //
    // Each card's visibility rule lives here once, shared by every layout.
    // `fillsPage` is the spread's alone: the card takes up its page's slack
    // (see `CardContentFrame`).

    @ViewBuilder private var wrappedButtonIfShown: some View {
        if hasAnyData { wrappedButton }
    }

    @ViewBuilder private func insightsCardIfShown(fillsPage: Bool = false) -> some View {
        if showInsights {
            insightsCard(fillsPage: fillsPage)
        }
    }

    private var showOutlook: Bool { !outlookRows.isEmpty && aiEnabled }

    @ViewBuilder private func outlookCardIfShown(fillsPage: Bool = false) -> some View {
        if showOutlook {
            outlookCard(outlookRows, fillsPage: fillsPage)
        }
    }

    private var showPatterns: Bool { patterns != nil && aiEnabled }

    @ViewBuilder private func patternsCardIfShown(fillsPage: Bool = false) -> some View {
        if showPatterns, let patterns {
            patternsCard(patterns, fillsPage: fillsPage)
        }
    }

    /// The last of the three AI cards that is showing — the one that takes
    /// up the slack of the spread's trailing page. Nil when none is.
    private var lastLeadCard: StatsLeadCard? {
        StatsLeadCard.last(insights: showInsights, outlook: showOutlook,
                           patterns: showPatterns)
    }

    @ViewBuilder private var accuracyCardIfShown: some View {
        if aiEnabled, timeAccuracy != nil || amountAccuracy != nil || sleepAccuracy != nil {
            accuracyCard
        }
    }

    @ViewBuilder private var careSummaryButtonIfShown: some View {
        if hasAnyData { careSummaryButton }
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

    // MARK: Care summary (printable pediatrician report)

    private var careSummaryButton: some View {
        Button { showCareSummary = true } label: {
            HStack(spacing: 12) {
                Text("🩺")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Care summary")
                        .font(.headline)
                        .foregroundStyle(AppColor.text)
                    Text("A printable report for \(babyName)'s checkups")
                        .font(.caption)
                        .foregroundStyle(AppColor.text2)
                }
                Spacer()
                Image(systemName: "doc.text")
                    .foregroundStyle(AppColor.accentFeed)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .surfaceCard(cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Care summary — a printable report for pediatrician visits")
    }

    // MARK: Insights (on-device AI)

    private func insightsCard(fillsPage: Bool = false) -> some View {
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
        .modifier(CardContentFrame(fillsPage: fillsPage))
        .padding(16)
        .surfaceCard(cornerRadius: 18)
    }

    private func loadSummary() async {
        guard aiEnabled, !feeds.isEmpty else { return }
        // Debounce: the `.task(id:)` above cancels and restarts this on every
        // event change, so a widget batch of N events would otherwise regenerate
        // the summary N times. Wait out the burst first — a superseded run cancels
        // here before doing the expensive generation.
        try? await Task.sleep(for: .seconds(0.8))
        guard !Task.isCancelled else { return }
        // The accuracy walk-forward and the outlook rows are pure Swift and
        // cheap (~10ms) — no Apple Intelligence hardware needed, unlike the
        // generated cards.
        loadAccuracy()
        loadOutlook()
        guard BabyIntelligence.isAvailable else { return }
        summaryLoading = true
        summary = await BabyIntelligence.summary(digest: buildDigest(), babyName: babyName)
        summaryLoading = false
        guard !Task.isCancelled else { return }
        // Last, and only on iOS 27: the cloud round-trip is the slow one, and
        // the two on-device cards should already be on screen while it runs.
        if #available(iOS 27, *) {
            patterns = await loadWeeklyPatterns()
        } else {
            patterns = nil
        }
    }

    /// Two weeks if it fits the cloud context, else ten days, else one week
    /// — a busy newborn's fortnight can outgrow the budget once notes and
    /// SNOO sleeps pile up.
    @available(iOS 27, *)
    private func loadWeeklyPatterns() async -> BabyIntelligence.WeeklyPatterns? {
        for days in [HistoryDigest.days, 10, HistoryDigest.minimumDaysWithData] {
            guard let history = buildHistoryDigest(days: days) else { return nil }
            guard await BabyIntelligence.cloudFits(history) else { continue }
            return await BabyIntelligence.weeklyPatterns(history: history, babyName: babyName)
        }
        return nil
    }

    /// Every event of the last `days`, for the cloud model — see
    /// `HistoryDigest` for why this is raw where `buildDigest` is totals.
    private func buildHistoryDigest(days: Int) -> String? {
        guard let baby = babies.first else { return nil }
        return HistoryDigest.render(
            babyName: babyName, dateOfBirth: baby.dateOfBirth,
            feeds: feeds.map { .init(at: $0.timestamp, oz: $0.amountOz) },
            sleeps: sleeps.map { .init(start: $0.startedAt, end: $0.endedAt) },
            diapers: diapers.map { .init(at: $0.timestamp, type: $0.type) },
            days: days)
    }

    /// Walk-forward accuracy over the trailing month (`PredictionAccuracy`).
    private func loadAccuracy() {
        guard let baby = babies.first,
              let settings = SharedSettings.canonical(settingsList) else { return }
        let feedTimes = feeds.map(\.timestamp)
        let feedPairs = feeds.map { ($0.timestamp, $0.amountOz) }
        timeAccuracy = PredictionAccuracy.feedTimeReport(
            feeds: feedTimes, dateOfBirth: baby.dateOfBirth,
            nightStartMinute: settings.nightStartMinute, nightEndMinute: settings.nightEndMinute,
            targetInterval: { settings.feedInterval(after: $0) })
        amountAccuracy = PredictionAccuracy.feedAmountReport(
            feeds: feedPairs, dateOfBirth: baby.dateOfBirth,
            nightStartMinute: settings.nightStartMinute, nightEndMinute: settings.nightEndMinute)
        sleepAccuracy = PredictionAccuracy.sleepDurationReport(
            sleeps: sleeps.map { ($0.startedAt, $0.endedAt) }, dateOfBirth: baby.dateOfBirth,
            nightStartMinute: settings.nightStartMinute, nightEndMinute: settings.nightEndMinute)
    }

    /// The outlook rows: the engine's numbers with their basis spelled out,
    /// assembled deterministically (`TodayOutlook`) — no generation step, so
    /// no hardware gate and nothing to hallucinate. Empty when no prediction
    /// clears the confidence floor, and the card hides.
    private func loadOutlook() {
        guard let baby = babies.first,
              let settings = SharedSettings.canonical(settingsList) else {
            outlookRows = []
            return
        }
        outlookRows = TodayOutlook.rows(
            feeds: feeds.map { ($0.timestamp, $0.amountOz) },
            sleeps: sleeps.map { ($0.startedAt, $0.endedAt) },
            dateOfBirth: baby.dateOfBirth,
            targetFeedInterval: { settings.feedInterval(after: $0) },
            nightStartMinute: settings.nightStartMinute,
            nightEndMinute: settings.nightEndMinute)
    }

    // MARK: Outlook (Phase 3) + accuracy (Phase 4)

    /// Structured predictions with the reasoning shown — computed, not
    /// generated, so unlike the insights and weekly cards it carries no
    /// gradient border and its caption says "computed."
    private func outlookCard(_ rows: [TodayOutlook.Row], fillsPage: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(AIGlow.mark) TODAY'S OUTLOOK")
                .font(.caption2.weight(.semibold))
                .kerning(0.8)
                .foregroundStyle(AIGlow.gradient)
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.title.uppercased())
                            .font(.caption2.weight(.semibold))
                            .kerning(0.6)
                            .foregroundStyle(AppColor.text2)
                        Spacer()
                        Text(row.value)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColor.text)
                    }
                    Text(row.basis)
                        .font(.caption2)
                        .foregroundStyle(AppColor.text3)
                }
            }
            Text("Computed on-device from \(babyName)'s recent patterns")
                .font(.caption2)
                .foregroundStyle(AppColor.text3)
        }
        .modifier(CardContentFrame(fillsPage: fillsPage))
        .padding(16)
        .surfaceCard(cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }

    /// The weekly card. Same gradient-border treatment as the outlook — all of
    /// it is generated — but its caption names Private Cloud Compute, because
    /// this is the one card whose input leaves the phone.
    private func patternsCard(_ patterns: BabyIntelligence.WeeklyPatterns,
                              fillsPage: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(AIGlow.mark) THIS WEEK'S PATTERNS")
                .font(.caption2.weight(.semibold))
                .kerning(0.8)
                .foregroundStyle(AIGlow.gradient)
            Text(patterns.headline)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.text)
            ForEach(patterns.observations, id: \.self) { observation in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(AIGlow.gradient)
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)
                    Text(observation)
                        .font(.subheadline)
                        .foregroundStyle(AppColor.text)
                }
            }
            Text("Analyzed by Apple's Private Cloud Compute from the last two weeks — never stored, never shared with us")
                .font(.caption2)
                .foregroundStyle(AppColor.text3)
        }
        .modifier(CardContentFrame(fillsPage: fillsPage))
        .padding(16)
        .surfaceCard(cornerRadius: 18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    LinearGradient(colors: AIGlow.colors.map { $0.opacity(0.35) },
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var accuracyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(AIGlow.mark) PREDICTION ACCURACY")
                .font(.caption2.weight(.semibold))
                .kerning(0.8)
                .foregroundStyle(AIGlow.gradient)
            if let report = timeAccuracy {
                accuracyRow(title: "Feed timing",
                            value: "median miss \(WakeWindow.shortLabel(report.statisticalMedianError))")
            }
            if let report = amountAccuracy {
                accuracyRow(title: "Bottle size",
                            value: "median miss \(OzFormat.string((report.statisticalMedianError * 4).rounded() / 4)) oz")
            }
            if let report = sleepAccuracy {
                accuracyRow(title: "Sleep length",
                            value: "median miss \(WakeWindow.shortLabel(report.statisticalMedianError))")
            }
            Text("Last 30 days, scored against what actually happened. \(modelStatusLine)")
                .font(.caption2)
                .foregroundStyle(AppColor.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .surfaceCard(cornerRadius: 18)
    }

    private func accuracyRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(AppColor.text2)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.text)
        }
    }

    /// Whether the Phase 2 personal model earned its spot anywhere.
    private var modelStatusLine: String {
        let wins = [timeAccuracy, amountAccuracy].compactMap { $0 }.contains { $0.modelWins }
        return wins
            ? "\(babyName)'s personal model is beating the baseline and is in use."
            : "Baseline statistics are in use; a personal model takes over only if it proves more accurate."
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

    /// `fillsPage`: on the spread's leading page the card takes the slack
    /// between the share row and the lifetime tiles — taller, its lines
    /// where they always were, at the top.
    private func recordHero(fillsPage: Bool = false) -> some View {
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
        .modifier(CardContentFrame(fillsPage: fillsPage))
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

    /// `twoColumn`: leading-aligns the empty line, in line with the card's
    /// title as the Today, Milestones and Teamwork cards already are; false is
    /// the phone's layout.
    private func nightShiftCard(twoColumn: Bool = false) -> some View {
        let shares = engine.nightShift(days: 7)
        let total = shares.reduce(0) { $0 + $1.count }
        return Card(title: "🌙 Night shift · this week") {
            if total == 0 {
                Text("No night feeds logged this week")
                    .font(.subheadline).foregroundStyle(AppColor.text3)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: twoColumn ? .leading : .center)
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
        // Each is a full-history pass; evaluate once, not twice.
        let hour = engine.hungriestHour()
        let note = cadenceNote
        return Card(title: "Patterns") {
            VStack(alignment: .leading, spacing: 12) {
                if let hour {
                    label("🕕 Hungriest hour", detail: "around \(Self.hourLabel(hour))")
                }
                if let note {
                    label("📅 On this day", detail: note)
                }
                if hour == nil && note == nil {
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
                    // Sleeps aren't attributed to a person, so the split
                    // covers feeds and diapers only — say so.
                    Text("\(total) feeds & diapers logged together")
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
    // `.formatted` styles: locale-aware (fixed "MMM d"/"h a" patterns aren't)
    // and backed by Foundation's own formatter cache — no per-call allocation.
    private static func monthDay(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
    private static func hourLabel(_ hour: Int) -> String {
        var c = DateComponents(); c.hour = hour
        let date = Calendar.current.date(from: c) ?? .now
        // "6 PM" for 12-hour users, "18" for 24-hour locales.
        return date.formatted(.dateTime.hour())
    }
}

/// The three AI cards that open the spread's trailing page, in the order
/// they stack: Insights, Today's outlook, This week's patterns.
enum StatsLeadCard: Equatable {
    case insights, outlook, patterns

    /// The last of them that is showing — the one that takes up its page's
    /// slack, so the first screen ends on the foot line whichever cards the
    /// day has. Nil when none is showing: the page then starts with the
    /// night shift and nothing stretches.
    static func last(insights: Bool, outlook: Bool, patterns: Bool) -> StatsLeadCard? {
        if patterns { return .patterns }
        if outlook { return .outlook }
        return insights ? .insights : nil
    }
}

/// How a Stats card's content sits inside its surface. Everywhere but the
/// spread's first screen it is the frame these cards have always had: as
/// wide as the card, as tall as the content. With `fillsPage` the frame
/// also takes whatever height its page has left — the padding and the
/// background come after it, so the surface is what grows — while the
/// content stays at the top, where it was.
private struct CardContentFrame: ViewModifier {
    let fillsPage: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if fillsPage {
            content
                // Never less than the content needs: handed too little (a
                // large text size on a short page) the card keeps every
                // line, and the page scrolls instead.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    StatsView()
        .modelContainer(AppModelContainer.preview)
        .preferredColorScheme(.dark)
}
