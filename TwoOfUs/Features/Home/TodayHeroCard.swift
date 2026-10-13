import SwiftUI

/// One day of daycare, aggregated for the cards. Built by HomeView from
/// today's Brightwheel-imported events.
struct DaycareDaySummary: Equatable {
    var feedCount = 0
    var feedOz: Double = 0
    var napCount = 0
    var napSeconds: TimeInterval = 0
    var diaperCount = 0
    /// Wet/dirty breakdown of `diaperCount` — a `.both` diaper counts toward
    /// each, the way parents and pediatricians tally them.
    var wetCount = 0
    var dirtyCount = 0
    var activityCount = 0
    var photoCount = 0
    var medicationCount = 0
    var checkIn: Date?          // first check-in of the day
    var checkOut: Date?         // last check-out of the day
    var hasAnythingElse = false // any other daycare event (note, mood, milestone…)

    var isEmpty: Bool {
        feedCount == 0 && napCount == 0 && diaperCount == 0 && activityCount == 0
            && photoCount == 0 && medicationCount == 0
            && checkIn == nil && checkOut == nil && !hasAnythingElse
    }
}

// MARK: - The hero (every day)

/// The storybook page of the day, and Home's one TODAY card in every
/// setting. A day-flow strip tells the day's actual shape — feeds and
/// diapers as emoji at their true times, naps as spans — with the whole-day
/// totals as three plain numbers beneath. On a home day that's the whole
/// card. Daycare arrives as layers on the same base: a neutral zone on
/// the strip from drop-off, the "daycare since" capsule, and one quiet
/// dotted recap line of what staff have logged (photos save individually
/// from the timeline; the recap only counts them).
/// While any sleep is running the strip's now edge glows and breathes;
/// a running Brightwheel nap also ticks into the sleep total live.
struct TodayHeroCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let babyName: String
    /// Today's events — home and daycare together — for the day-flow strip.
    let marks: [RibbonMark]
    /// Whole-day totals (home + daycare).
    let feedCount: Int
    let feedOz: Double
    let diaperCount: Int
    /// Whole-day wet/dirty tallies (a `.both` diaper counts toward each).
    let wetCount: Int
    let dirtyCount: Int
    let sleepSeconds: TimeInterval
    /// The daycare-only slice; `.init()` (empty) on a pure home day.
    let daycare: DaycareDaySummary
    /// Non-nil while he's at daycare: when that day began (check-in, or the
    /// first daycare event). Drives the "since" capsule and the open zone.
    let attendingSince: Date?
    /// The first daycare-logged event of the day — the check-in stand-in for
    /// the strip zone and capsule AFTER pickup, when `attendingSince` is gone.
    /// Real Brightwheel days often never get explicit check markers, and the
    /// finished day must not vanish off the strip at 5:30.
    var firstDaycareEventAt: Date? = nil
    /// The last daycare-logged event of the day — the check-out stand-in on
    /// marker-less days: it closes the capsule's window and the strip zone at
    /// the last thing staff logged instead of the assumed 5:30.
    var lastDaycareEventAt: Date? = nil
    /// Start of a nap Brightwheel has begun but not ended — drawn on the
    /// strip (its SleepEvent doesn't exist yet) and counted into the total.
    let liveNapStartedAt: Date?
    /// Start of a parent-logged sleep still running (already on the strip
    /// via `marks`; this only drives the glow and the live caption).
    var activeSleepStartedAt: Date? = nil
    let now: Date
    var showFeed = true
    var showSleep = true
    var showDiaper = true

    private enum Stat { case feed, diaper, sleep }
    @State private var popped: Set<Stat> = []
    @State private var breathing = false

    /// Any sleep in progress — Brightwheel's or a parent-logged one.
    private var sleepingSince: Date? { liveNapStartedAt ?? activeSleepStartedAt }

    /// Seconds of the Brightwheel nap still running — counted into the sleep
    /// totals live (its SleepEvent only lands when staff log the wake).
    private var liveNapSeconds: TimeInterval {
        liveNapStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
    }

    /// Today's share of the parent/SNOO sleep still running. StatsEngine only
    /// counts finished sleeps, so the big total would otherwise sit frozen
    /// while the caption beneath it ticks "asleep · 43m". Clamped to midnight
    /// — an overnight stretch's earlier hours belong to yesterday's total.
    private var activeSleepSeconds: TimeInterval {
        guard let start = activeSleepStartedAt else { return 0 }
        let todayStart = Calendar.current.startOfDay(for: now)
        return max(0, now.timeIntervalSince(max(start, todayStart)))
    }

    private var sleepTotal: TimeInterval {
        sleepSeconds + liveNapSeconds + activeSleepSeconds
    }

    /// When the daycare day began: the real check-in marker, else the first
    /// daycare-logged event — same fallback `DaycareStatus` uses live.
    private var daycareDayStart: Date? { daycare.checkIn ?? firstDaycareEventAt }

    /// When it ended: the real check-out marker, else the last thing staff
    /// logged. Nil only when neither exists.
    private var daycareDayEnd: Date? { daycare.checkOut ?? lastDaycareEventAt }

    /// The strip's daycare zone: open-ended while he's there, the recorded
    /// (or inferred) span after pickup — assumed 5:30 as the last resort.
    private var zone: (start: Date, end: Date?)? {
        if let attendingSince { return (attendingSince, nil) }
        guard let start = daycareDayStart else { return nil }
        let assumed = Calendar.current.date(bySettingHour: DaycareStatus.assumedCheckOutHour,
                                            minute: DaycareStatus.assumedCheckOutMinute,
                                            second: 0, of: now)
        guard let end = daycareDayEnd ?? assumed else { return nil }
        return (start, min(end, now))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                // "Today", not "<name>'s Day" — his name sits right above in
                // the profile header. Rounded title3 like the log tiles'
                // titles: the eyebrow idiom the smaller cards use was tried
                // and read smaller than the capsule beside it — too quiet to
                // anchor the hero.
                Text("Today")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(AppColor.text)
                Spacer()
                // Today's date — the daycare window lives on the Daycare
                // recap row now, where the place's numbers already are.
                Text(now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.subheadline)
                    .foregroundStyle(AppColor.text2)
            }

            // The day's actual shape, then its totals as three plain numbers.
            VStack(spacing: 14) {
                DayFlowStrip(marks: marks, zone: zone,
                             liveNapStartedAt: liveNapStartedAt,
                             glowStart: sleepingSince, now: now)
                    .frame(height: 62)
                // Tiered sizing, never truncation: minimumScaleFactor does
                // NOT reliably scale a concatenated multi-font Text — it
                // truncates ("10 diape…", the TestFlight bug) — so the rigid
                // tiers measure every value at its TRUE width and ViewThatFits
                // steps the whole row down together (36 → 31) when a long day
                // or a large Dynamic Type setting overflows. The last tier is
                // flexible so something always fits.
                ViewThatFits(in: .horizontal) {
                    totalsRow(valueSize: 28, rigid: true)
                    totalsRow(valueSize: 25, rigid: true)
                    totalsRow(valueSize: 22, rigid: true)
                    totalsRow(valueSize: 19, rigid: true)
                    // The floor, for accessibility text sizes: the three
                    // stats stack vertically — still full-size, still whole,
                    // never truncated.
                    VStack(alignment: .leading, spacing: 10) {
                        totalsColumns(valueSize: 27, rigid: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
            }

            // The daycare recap — what staff logged since drop-off (the
            // totals + strip above already carry the home side). A pure
            // home day ends at the totals. Photos save individually from
            // the timeline; the recap only counts them.
            if !daycare.isEmpty {
                bottomSection
            }
        }
        .padding(16)
        .background {
            // The storybook wash, as a sunrise band: the three event accents
            // across the top of the card in the totals' own order (feed teal
            // → diaper peach → sleep lavender), fading out high so the body
            // stays the standard card surface — special at a glance, calm
            // where the numbers live.
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [AppColor.accentFeed.opacity(0.35),
                                              AppColor.accentDiaper.opacity(0.33),
                                              AppColor.accentSleep.opacity(0.28)],
                                     startPoint: .leading, endPoint: .trailing))
                .mask(LinearGradient(stops: [.init(color: .white, location: 0),
                                             .init(color: .clear, location: 0.25)],
                                     startPoint: .top, endPoint: .bottom))
        }
        .surfaceCard(cornerRadius: 18)
        .onChange(of: feedOz) { old, new in if new > old { pop(.feed) } }
        .onChange(of: diaperCount) { old, new in if new > old { pop(.diaper) } }
        .onChange(of: sleepSeconds) { old, new in if new > old { pop(.sleep) } }
        .onChange(of: sleepingSince) { old, new in
            if new != nil, old == nil { pop(.sleep) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        // Stable hook for UI tests (doesn't affect the VoiceOver label above).
        .accessibilityIdentifier("todayCard")
    }

    /// The Daycare row's second label line: live during attendance, the
    /// recorded (or inferred) window after pickup. Compact clocks — the slot
    /// is narrow and the day half is obvious.
    private var daycareWindowText: String? {
        if let attendingSince {
            return "since \(TimeFormatting.clockCompact(attendingSince))"
        }
        guard let start = daycareDayStart else { return nil }
        if let end = daycareDayEnd, end > start {
            return "\(TimeFormatting.clockCompact(start)) – \(TimeFormatting.clockCompact(end))"
        }
        return "from \(TimeFormatting.clockCompact(start))"
    }

    // MARK: Totals

    /// One value as (text, isUnit) segments: digits at display scale, units
    /// ("oz", "diapers", the h/m inside a duration) in the small rounded
    /// style — concatenated Text so the mix shares one baseline.
    private func valueText(_ segments: [(String, Bool)], active: Bool, accent: Color,
                           size: CGFloat) -> Text {
        segments.map { text, isUnit in
            Text(text)
                .font(isUnit ? .system(.callout, design: .rounded).weight(.semibold)
                             : AppFont.display(size))
                .foregroundStyle(active ? (isUnit ? accent.opacity(0.7) : accent)
                                        : AppColor.text3)
        }.reduce(Text(""), +)
    }

    /// One size tier of the totals row: natural-width columns, flexible gaps.
    /// Rigid tiers hold their true width (no shrink, no truncation) so
    /// ViewThatFits can measure them honestly.
    private func totalsRow(valueSize: CGFloat, rigid: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if showFeed {
                feedColumn(valueSize: valueSize, rigid: rigid)
                if showDiaper || showSleep { Spacer(minLength: 12) }
            }
            if showDiaper {
                diaperColumn(valueSize: valueSize, rigid: rigid)
                if showSleep { Spacer(minLength: 12) }
            }
            if showSleep {
                sleepColumn(valueSize: valueSize, rigid: rigid)
            }
        }
    }

    /// The same three columns bare, for the stacked accessibility floor.
    @ViewBuilder
    private func totalsColumns(valueSize: CGFloat, rigid: Bool) -> some View {
        if showFeed { feedColumn(valueSize: valueSize, rigid: rigid) }
        if showDiaper { diaperColumn(valueSize: valueSize, rigid: rigid) }
        if showSleep { sleepColumn(valueSize: valueSize, rigid: rigid) }
    }

    private func feedColumn(valueSize: CGFloat, rigid: Bool) -> some View {
        totalColumn(.feed,
                    active: feedCount > 0,
                    segments: feedCount > 0
                        ? [(OzFormat.string(feedOz), false), (" oz", true)]
                        : [("—", false)],
                    caption: feedCount > 0 ? Plural.count(feedCount, "feed") : "no feeds yet",
                    valueSize: valueSize, rigid: rigid)
    }

    private func diaperColumn(valueSize: CGFloat, rigid: Bool) -> some View {
        totalColumn(.diaper,
                    active: diaperCount > 0,
                    segments: diaperCount > 0
                        ? [("\(diaperCount)", false),
                           (diaperCount == 1 ? " diaper" : " diapers", true)]
                        : [("—", false)],
                    caption: diaperCaption,
                    valueSize: valueSize, rigid: rigid)
    }

    private func sleepColumn(valueSize: CGFloat, rigid: Bool) -> some View {
        totalColumn(.sleep,
                    active: sleepingSince != nil || sleepSeconds > 0,
                    segments: sleepSegments,
                    caption: "sleep",
                    valueSize: valueSize, rigid: rigid,
                    liveSleep: sleepingSince != nil)
    }

    /// Whole-day sleep as segments — "8h 20m" with the h/m styled like the
    /// other columns' units, mid-nap ticking live via `sleepTotal`.
    private var sleepSegments: [(String, Bool)] {
        guard sleepTotal > 0 else { return [("—", false)] }
        let mins = Int(sleepTotal / 60)
        let h = mins / 60, m = mins % 60
        var segments: [(String, Bool)] = []
        if h > 0 { segments += [("\(h)", false), ("h", true)] }
        if m > 0 || h == 0 {
            segments += [(h > 0 ? " \(m)" : "\(m)", false), ("m", true)]
        }
        return segments
    }

    private func totalColumn(_ stat: Stat, active: Bool,
                             segments: [(String, Bool)], caption: String,
                             valueSize: CGFloat, rigid: Bool,
                             liveSleep: Bool = false) -> some View {
        VStack(spacing: 2) {
            // No emoji here: the strip above already tells each event's story
            // in glyphs, and the accent-inked numeral + caption identify the
            // stat on their own. The numbers get the whole stage. (Glance
            // values are display-scale — the type ramp's rule #1.)
            valueText(segments, active: active, accent: accent(for: stat), size: valueSize)
                .lineLimit(1)
                .fixedSize(horizontal: rigid, vertical: false)
                .minimumScaleFactor(rigid ? 1 : 0.7)
                .scaleEffect(popped.contains(stat) ? 1.12 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.55),
                           value: popped)

            if liveSleep, let start = sleepingSince {
                // The sleep's pulse, breathing with the strip's glow dot.
                // "napping" during the daycare day, "asleep" anywhere else —
                // a 3 AM stretch at home isn't a nap.
                HStack(spacing: 3) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.caption.weight(.semibold))
                    Text("\(liveNapStartedAt != nil || attendingSince != nil ? "napping" : "asleep") · \(TimeFormatting.duration(from: start, to: now))")
                        .monospacedDigit()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent(for: .sleep))
                .opacity(reduceMotion ? 1 : (breathing ? 1 : 0.55))
                .animation(reduceMotion ? nil
                           : .easeInOut(duration: 2.6).repeatForever(autoreverses: true),
                           value: breathing)
                .onAppear { if !reduceMotion { breathing = true } }
                .onDisappear { breathing = false }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            } else {
                Text(caption)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColor.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private var diaperCaption: String {
        guard diaperCount > 0 else { return "changes" }
        var parts: [String] = []
        if wetCount > 0 { parts.append("\(wetCount) wet") }
        if dirtyCount > 0 { parts.append("\(dirtyCount) dirty") }
        return parts.isEmpty ? Plural.count(diaperCount, "change")
                             : parts.joined(separator: " · ")
    }

    /// The same accents the rest of the app uses for these event types —
    /// the strip, the timeline, History — so the totals stay in family.
    private func accent(for stat: Stat) -> Color {
        switch stat {
        case .feed:   AppColor.accentFeed
        case .diaper: AppColor.accentDiaper
        case .sleep:  AppColor.accentSleep
        }
    }

    /// A short grow-and-settle when a stat gains a new event — the moment a
    /// fresh entry lands, from either home or the daycare feed.
    private func pop(_ stat: Stat) {
        guard !reduceMotion else { return }
        popped.insert(stat)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.45))
            popped.remove(stat)
        }
    }

    /// Whole-day sleep; mid-nap the running nap joins the count live, so the
    /// ring's center ticks. Same "4h 50m" spelling as the split rows below —
    /// one format everywhere.
    private var sleepValue: String {
        sleepTotal > 0 ? TimeFormatting.duration(minutes: Int(sleepTotal / 60)) : "—"
    }

    // MARK: Daycare recap

    /// One quiet daycare line: each metric led by its emoji, the same
    /// glyphs as the totals above, so the row scans without reading.
    /// The home side stays implicit — the strip and totals above already
    /// tell it. Activities live on the timeline; medication keeps its own
    /// red row below, where it can never blend in.
    private var bottomSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                iconDisc("building.2.fill", tint: AppColor.text2)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Daycare")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppColor.text)
                    // The attendance window, under its own roof: "since 7:51"
                    // while he's there, "7:51 – 4:15" once he's home.
                    if let daycareWindowText {
                        Text(daycareWindowText)
                            .font(.caption2)
                            .foregroundStyle(AppColor.text2)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(width: 60, alignment: .leading)
                HStack(spacing: 12) {
                    if daycare.feedCount > 0 {
                        emojiItem("🍼",
                                  "\(OzFormat.string(daycare.feedOz)) oz (\(daycare.feedCount))")
                    }
                    if daycare.diaperCount > 0 {
                        // Both kinds compact to a total — "1 wet · 1 dirty"
                        // overflows the one line; the whole-day split is
                        // already in the diaper total's caption above.
                        emojiItem("💧",
                                  daycare.wetCount > 0 && daycare.dirtyCount > 0
                                      ? "\(daycare.diaperCount)"
                                      : daycareDiaperWords)
                    }
                    if daycare.napSeconds + liveNapSeconds > 0 {
                        emojiItem("💤",
                                  TimeFormatting.duration(minutes: Int((daycare.napSeconds + liveNapSeconds) / 60)))
                    }
                    // Photos only — activities live on the timeline; the
                    // recap keeps its one-line promise.
                    if daycare.photoCount > 0 {
                        emojiItem("📸", "\(daycare.photoCount)")
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
            }
            medsRow
        }
    }

    @ViewBuilder private var medsRow: some View {
        if daycare.medicationCount > 0 {
            splitRow(systemImage: "pills.fill", tint: AppColor.accentMedication,
                     title: "Meds",
                     text: "\(Plural.count(daycare.medicationCount, "medication")) — see timeline",
                     textTint: AppColor.accentMedication)
        }
    }

    private func emojiItem(_ emoji: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Text(emoji)
                .font(.caption)
            Text(text)
                .font(.footnote)
                .foregroundStyle(AppColor.text2)
                .monospacedDigit()
        }
    }

    private var daycareDiaperWords: String {
        var parts: [String] = []
        if daycare.wetCount > 0 { parts.append("\(daycare.wetCount) wet") }
        if daycare.dirtyCount > 0 { parts.append("\(daycare.dirtyCount) dirty") }
        return parts.isEmpty ? Plural.count(daycare.diaperCount, "change")
                             : parts.joined(separator: " · ")
    }

    private func iconDisc(_ systemImage: String, tint: Color) -> some View {
        ZStack {
            Circle().fill(tint.opacity(0.13)).frame(width: 26, height: 26)
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
        }
    }

    /// One labeled row: a small tinted icon disc, a fixed-width title so
    /// the recap rows align, and the values on one quiet line.
    private func splitRow(systemImage: String, tint: Color, title: String,
                          text: String, textTint: Color) -> some View {
        HStack(spacing: 9) {
            iconDisc(systemImage, tint: tint)
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppColor.text)
                .frame(width: 60, alignment: .leading)
            Text(text)
                .font(.footnote)
                .foregroundStyle(textTint)
                .monospacedDigit()
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
    }

    private var accessibilitySummary: String {
        var parts: [String]
        if let attendingSince {
            parts = ["\(babyName) is at daycare since \(TimeFormatting.clock(attendingSince))"]
        } else {
            parts = ["\(babyName)'s day so far"]
        }
        if let start = sleepingSince {
            parts.append("asleep right now, \(TimeFormatting.duration(from: start, to: now)) so far")
        }
        var today: [String] = []
        if showFeed, feedCount > 0 {
            today.append("\(OzFormat.string(feedOz)) ounces across \(Plural.count(feedCount, "feed"))")
        }
        if showDiaper, diaperCount > 0 {
            today.append(diaperCaption.replacingOccurrences(of: " · ", with: ", ") + " diapers")
        }
        if showSleep, sleepTotal > 0 {
            today.append("\(sleepValue) of sleep")
        }
        if !today.isEmpty {
            parts.append("today: " + today.joined(separator: ", "))
        }
        var recap: [String] = []
        if daycare.feedCount > 0 {
            recap.append("\(OzFormat.string(daycare.feedOz)) ounces across \(Plural.count(daycare.feedCount, "feed"))")
        }
        if daycare.diaperCount > 0 {
            recap.append(daycareDiaperWords.replacingOccurrences(of: " · ", with: ", ") + " diapers")
        }
        let nap = daycare.napSeconds + liveNapSeconds
        if nap > 0 {
            recap.append("\(TimeFormatting.duration(minutes: Int(nap / 60))) of naps")
        }
        if daycare.photoCount > 0 {
            recap.append(Plural.count(daycare.photoCount, "photo"))
        }
        if !daycare.isEmpty || attendingSince != nil {
            parts.append("at daycare: " + (recap.isEmpty ? "nothing yet" : recap.joined(separator: ", ")))
        }
        if daycare.medicationCount > 0 {
            parts.append("\(Plural.count(daycare.medicationCount, "medication")) given, see the timeline")
        }
        return parts.joined(separator: ", ")
    }
}

/// The day as a horizontal time strip: a soft track spanning the whole
/// day, midnight to midnight, the daycare window as a neutral wash (open-ended and fading while
/// he's there, a closed span after pickup, absent on a home day), naps as
/// slim lavender lozenges in the band, feeds as 🍼 above it, diapers as
/// 💧/💩 below, sparse hour labels underneath. Any
/// running sleep puts a breathing glow dot at the now edge.
private struct DayFlowStrip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let marks: [RibbonMark]
    /// The daycare window; `end == nil` means still there (fade into now).
    let zone: (start: Date, end: Date?)?
    /// Start of a Brightwheel nap still running — drawn as its own span,
    /// since its SleepEvent isn't in the store (and `marks`) yet.
    let liveNapStartedAt: Date?
    /// Start of any in-progress sleep: the breathing glow at the now edge.
    let glowStart: Date?
    let now: Date

    @State private var glowBreathing = false

    private let calendar = Calendar.current

    var body: some View {
        GeometryReader { geo in
            content(size: geo.size)
        }
        .accessibilityHidden(true)
    }

    private func content(size: CGSize) -> some View {
        let dayStart = calendar.startOfDay(for: now)
        let window = hourWindow(dayStart: dayStart)
        func hour(_ d: Date) -> Double { d.timeIntervalSince(dayStart) / 3600 }
        func x(_ h: Double) -> CGFloat {
            CGFloat((min(max(h, window.start), window.end) - window.start)
                    / (window.end - window.start)) * size.width
        }
        let bandY = size.height * 0.32
        let bandH = size.height * 0.30
        let nowX = x(hour(now))

        return ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    // Track — full card2, no fade: at 0.8 over the dark card
                    // the whole strip nearly vanished.
                    let band = CGRect(x: 0, y: bandY, width: size.width, height: bandH)
                    ctx.fill(Path(roundedRect: band, cornerRadius: bandH / 2),
                             with: .color(AppColor.card2))

                    // Daycare zone. A place, not an event — so a neutral
                    // wash, NOT a palette color: teal here read as feed
                    // territory under the feed dots. Open-ended, it fades
                    // toward now (the day still being written); after
                    // pickup it sits as a flat, finished span.
                    if let zone {
                        let ongoing = zone.end == nil
                        let endX = x(hour(zone.end ?? now))
                        let rect = CGRect(x: x(hour(zone.start)), y: bandY,
                                          width: max(bandH, endX - x(hour(zone.start))),
                                          height: bandH)
                        let path = Path(roundedRect: rect, cornerRadius: bandH / 2)
                        if ongoing {
                            ctx.fill(path, with: .linearGradient(
                                Gradient(colors: [AppColor.text2.opacity(0.30),
                                                  AppColor.text2.opacity(0.10)]),
                                startPoint: CGPoint(x: rect.minX, y: 0),
                                endPoint: CGPoint(x: rect.maxX, y: 0)))
                        } else {
                            ctx.fill(path, with: .color(AppColor.text2.opacity(0.22)))
                        }
                        let glyph = ctx.resolve(Text(Image(systemName: "building.2.fill"))
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(AppColor.text2))
                        ctx.draw(glyph, at: CGPoint(x: rect.minX + 8, y: rect.midY), anchor: .center)
                    }

                    // Naps (overnight tail clips to the window's left edge)
                    func nap(from: Double, to: Double, live: Bool) {
                        let h: CGFloat = max(9, bandH - 7)
                        let x0 = x(from), x1 = x(to)
                        let r = CGRect(x: x0, y: bandY + (bandH - h) / 2,
                                       width: max(h, x1 - x0), height: h)
                        ctx.fill(Path(roundedRect: r, cornerRadius: h / 2),
                                 with: .color(AppColor.accentSleep.opacity(live ? 0.9 : 0.55)))
                    }
                    for mark in marks where mark.kind == .sleep {
                        nap(from: hour(mark.start), to: hour(mark.end ?? now), live: false)
                    }
                    if let start = liveNapStartedAt {
                        nap(from: hour(start), to: hour(now), live: true)
                    }

                    // Feeds above, diapers below — each event as its emoji, so the
                    // strip reads at a glance (🍼 lands before "feed" does).
                    func emojiMark(_ h: Double, _ emoji: String, above: Bool) {
                        let y = above ? bandY - 8 : bandY + bandH + 8
                        let glyph = ctx.resolve(Text(emoji).font(.system(size: 10)))
                        // Clamp inside the strip so an event at the window's
                        // edge doesn't draw a half-clipped glyph.
                        ctx.draw(glyph, at: CGPoint(x: min(max(x(h), 6), size.width - 6), y: y),
                                 anchor: .center)
                    }
                    for mark in marks where mark.kind == .feed {
                        emojiMark(hour(mark.start), "🍼", above: true)
                    }
                    for mark in marks where mark.kind == .diaper {
                        // A .both diaper shows 💩 — the saltier half of the news.
                        emojiMark(hour(mark.start),
                                  mark.diaperType == .wet ? "💧" : "💩",
                                  above: false)
                    }

                    // The "now" edge, marked even outside a sleep
                    if glowStart == nil {
                        ctx.stroke(
                            Path(ellipseIn: CGRect(x: nowX - 3, y: bandY + bandH / 2 - 3,
                                                   width: 6, height: 6)),
                            with: .color(AppColor.text2), lineWidth: 1.5)
                    }

                    // Sparse hour labels — the day's quarter marks.
                    var h = window.start
                    while h <= window.end {
                        let t = ctx.resolve(Text(hourLabel(Int(h)))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(AppColor.text2))
                        ctx.draw(t, at: CGPoint(x: min(max(x(h), 7), size.width - 9),
                                                y: size.height - 4), anchor: .center)
                        h += 6
                    }
                }

                // The living part: a breathing glow where sleep meets now.
                if glowStart != nil {
                    ZStack {
                        Circle()
                            .fill(AppColor.accentSleep.opacity(0.45))
                            .frame(width: 18, height: 18)
                            .blur(radius: 5)
                            .scaleEffect(glowBreathing ? 1.5 : 0.8)
                            .animation(reduceMotion ? nil
                                       : .easeInOut(duration: 2.6).repeatForever(autoreverses: true),
                                       value: glowBreathing)
                        Circle()
                            .fill(.white.opacity(0.9))
                            .frame(width: 6, height: 6)
                    }
                    .position(x: nowX, y: bandY + bandH / 2)
                    .onAppear { if !reduceMotion { glowBreathing = true } }
                    .onDisappear { glowBreathing = false }
                }
            }
    }

    /// The whole calendar day, midnight to midnight — a fixed scale, so an
    /// hour is always the same width and the day fills in left to right.
    private func hourWindow(dayStart: Date) -> (start: Double, end: Double) {
        (0, 24)
    }

    private func hourLabel(_ h: Int) -> String {
        switch h {
        case 0, 24: "12a"
        case 12: "12p"
        case ..<12: "\(h)a"
        default: "\(h - 12)p"
        }
    }
}

private func previewMarks() -> [RibbonMark] {
    let cal = Calendar.current
    func at(_ h: Int, _ m: Int) -> Date {
        cal.date(bySettingHour: h, minute: m, second: 0, of: .now) ?? .now
    }
    return [
        RibbonMark(kind: .sleep, start: cal.startOfDay(for: .now), end: at(6, 30)),
        RibbonMark(kind: .feed, start: at(6, 45)),
        RibbonMark(kind: .diaper, start: at(7, 0), diaperType: .wet),
        RibbonMark(kind: .feed, start: at(9, 0)),
        RibbonMark(kind: .sleep, start: at(9, 45), end: at(10, 30)),
        RibbonMark(kind: .diaper, start: at(10, 45), diaperType: .dirty),
        RibbonMark(kind: .feed, start: at(12, 0)),
    ]
}

#Preview("Hero, at daycare, napping") {
    TodayHeroCard(
        babyName: "Miller",
        marks: previewMarks(),
        feedCount: 3, feedOz: 7, diaperCount: 3, wetCount: 2, dirtyCount: 1,
        sleepSeconds: 4 * 3600 + 50 * 60,
        daycare: {
            var d = DaycareDaySummary()
            d.feedCount = 1; d.feedOz = 2; d.diaperCount = 1
            d.wetCount = 1
            d.napCount = 1; d.napSeconds = 40 * 60
            d.activityCount = 2; d.photoCount = 3
            d.checkIn = .now.addingTimeInterval(-69 * 60)
            return d
        }(),
        attendingSince: .now.addingTimeInterval(-69 * 60),
        liveNapStartedAt: .now.addingTimeInterval(-12 * 60),
        now: .now
    )
    .padding()
    .background(AppColor.bg)
    .preferredColorScheme(.dark)
}

#Preview("Hero, home day") {
    TodayHeroCard(
        babyName: "Miller",
        marks: previewMarks(),
        feedCount: 3, feedOz: 7, diaperCount: 3, wetCount: 2, dirtyCount: 1,
        sleepSeconds: 4 * 3600 + 50 * 60,
        daycare: DaycareDaySummary(),
        attendingSince: nil,
        liveNapStartedAt: nil,
        activeSleepStartedAt: .now.addingTimeInterval(-25 * 60),
        now: .now
    )
    .padding()
    .background(AppColor.bg)
}
