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

// MARK: - The hero (while he's at daycare)

/// The storybook page of Miller's day, shown while he's at daycare in place
/// of BOTH the TODAY card and the daycare card — they were the same three
/// numbers in two formats. A day-flow strip tells the day's actual shape —
/// feeds and diapers as dots at their true times, naps as spans, the
/// daycare window tinted from drop-off and fading out at "now" — with the
/// whole-day totals as three plain numbers beneath. Mid-nap the strip's
/// leading edge glows and breathes while the sleep total ticks live. One
/// quiet dotted line underneath recaps what daycare has logged since
/// drop-off (the home side stays implicit in the strip and totals).
/// Checkout dissolves it back into the plain TODAY card plus the quiet
/// finished-day card below.
struct DaycareDayHeroCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let babyName: String
    /// Today's events — home and daycare together — for the day-flow strip.
    let marks: [RibbonMark]
    /// Whole-day totals (home + daycare), same numbers the TODAY card showed.
    let feedCount: Int
    let feedOz: Double
    let diaperCount: Int
    /// Whole-day wet/dirty tallies (a `.both` diaper counts toward each).
    let wetCount: Int
    let dirtyCount: Int
    let sleepSeconds: TimeInterval
    /// The daycare-only slice, for the split row.
    let daycare: DaycareDaySummary
    /// When the daycare day began (check-in, or the first daycare event).
    let since: Date
    /// Start of a nap Brightwheel has begun but not ended.
    let liveNapStartedAt: Date?
    let now: Date
    var showFeed = true
    var showSleep = true
    var showDiaper = true
    /// Batch-saves the day's daycare photos to the camera roll (HomeView
    /// owns the events and the toast). Nil hides the affordance.
    var onSavePhotos: (() -> Void)? = nil

    private enum Stat { case feed, diaper, sleep }
    @State private var popped: Set<Stat> = []
    @State private var breathing = false

    private var napping: Bool { liveNapStartedAt != nil }

    /// Seconds of the Brightwheel nap still running — counted into the sleep
    /// totals live (its SleepEvent only lands when staff log the wake).
    private var liveNapSeconds: TimeInterval {
        liveNapStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
    }

    private var sleepTotal: TimeInterval { sleepSeconds + liveNapSeconds }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                // "Today", not "<name>'s Day" — his name sits right above in
                // the profile header, and the TODAY card uses the same word
                // on non-daycare days, so the slot reads consistently.
                Text("Today")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(AppColor.text)
                Spacer()
                // Neutral like the strip's daycare zone — a place, not an
                // event, so it stays out of the feed-teal family.
                HStack(spacing: 4) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text("daycare since \(TimeFormatting.clock(since))")
                        .monospacedDigit()
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppColor.text2)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(AppColor.text2.opacity(0.10), in: Capsule())
            }

            // The day's actual shape, then its totals as three plain numbers.
            VStack(spacing: 14) {
                DayFlowStrip(marks: marks, since: since,
                             liveNapStartedAt: liveNapStartedAt, now: now)
                    .frame(height: 62)
                HStack(alignment: .top, spacing: 10) {
                    if showFeed {
                        totalColumn(.feed,
                                    active: feedCount > 0,
                                    value: feedCount > 0 ? OzFormat.string(feedOz) : "—",
                                    unit: feedCount > 0 ? "oz" : nil,
                                    caption: feedCount > 0 ? Plural.count(feedCount, "feed") : "no feeds yet")
                    }
                    if showDiaper {
                        totalColumn(.diaper,
                                    active: diaperCount > 0,
                                    value: diaperCount > 0 ? "\(diaperCount)" : "—",
                                    unit: nil,
                                    caption: diaperCaption)
                    }
                    if showSleep {
                        totalColumn(.sleep,
                                    active: napping || sleepSeconds > 0,
                                    value: sleepValue,
                                    unit: nil,
                                    caption: "sleep",
                                    liveNap: napping)
                    }
                }
            }

            // The daycare recap — what staff logged since drop-off (the
            // totals + strip above already carry the home side).
            bottomSection
            if let onSavePhotos, daycare.photoCount > 0 {
                SavePhotosButton(count: daycare.photoCount, action: onSavePhotos)
            }
        }
        .padding(16)
        .background(
            // The storybook wash: warm peach rising into lavender, laid over
            // the standard card color so hairline + dark mode stay in family.
            LinearGradient(colors: [AppColor.accentDiaper.opacity(0.12),
                                    AppColor.accentSleep.opacity(0.14)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 20)
        )
        .surfaceCard(cornerRadius: 20)
        .onChange(of: feedOz) { old, new in if new > old { pop(.feed) } }
        .onChange(of: diaperCount) { old, new in if new > old { pop(.diaper) } }
        .onChange(of: sleepSeconds) { old, new in if new > old { pop(.sleep) } }
        .onChange(of: liveNapStartedAt) { old, new in
            if new != nil, old == nil { pop(.sleep) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        // The combine above folds the Save button's tap away from VoiceOver —
        // expose it as a custom action on the card element instead.
        .accessibilityActions {
            if let onSavePhotos, daycare.photoCount > 0 {
                Button("Save daycare photos to camera roll", action: onSavePhotos)
            }
        }
        // Stable hook for UI tests (doesn't affect the VoiceOver label above).
        .accessibilityIdentifier("daycareCard")
    }

    // MARK: Totals

    private func totalColumn(_ stat: Stat, active: Bool, value: String,
                             unit: String?, caption: String,
                             liveNap: Bool = false) -> some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    // Ink in the stat's own pastel family, not stark black.
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(active ? ink(for: stat) : AppColor.text3)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                if let unit {
                    Text(unit)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(active ? ink(for: stat).opacity(0.7) : AppColor.text3)
                }
            }
            .scaleEffect(popped.contains(stat) ? 1.12 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.55),
                       value: popped)

            if liveNap, let start = liveNapStartedAt {
                // The nap's pulse, breathing with the strip's glow dot.
                HStack(spacing: 3) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 8, weight: .semibold))
                    Text("napping · \(TimeFormatting.duration(from: start, to: now))")
                        .monospacedDigit()
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ink(for: .sleep))
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
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppColor.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var diaperCaption: String {
        guard diaperCount > 0 else { return "changes" }
        var parts: [String] = []
        if wetCount > 0 { parts.append("\(wetCount) wet") }
        if dirtyCount > 0 { parts.append("\(dirtyCount) dirty") }
        return parts.isEmpty ? Plural.count(diaperCount, "change")
                             : parts.joined(separator: " · ")
    }

    /// Darker siblings of the pastel accents for the value text — and in
    /// dark mode the opposite: lighter ones, since the pastel fill is dim
    /// there and a dark ink would sink into it.
    private func ink(for stat: Stat) -> Color {
        switch (stat, colorScheme == .dark) {
        case (.feed, false):   Color(hex: "1E6B5E")
        case (.feed, true):    Color(hex: "9FE8DA")
        case (.diaper, false): Color(hex: "7A5220")
        case (.diaper, true):  Color(hex: "F4D1A0")
        case (.sleep, false):  Color(hex: "45459E")
        case (.sleep, true):   Color(hex: "C2C2FF")
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

    /// One quiet daycare line, no emoji: tiny dots in each metric's strip
    /// color carry the meaning the emoji used to, and the home side stays
    /// implicit — the strip and totals above already tell it. Activities
    /// live on the timeline; medication keeps its own red row below, where
    /// it can never blend in.
    private var bottomSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                iconDisc("building.2.fill", tint: AppColor.text2)
                Text("Daycare")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.text)
                    .frame(width: 52, alignment: .leading)
                HStack(spacing: 10) {
                    if daycare.feedCount > 0 {
                        dotItem(AppColor.accentFeed,
                                "\(OzFormat.string(daycare.feedOz)) oz (\(daycare.feedCount))")
                    }
                    if daycare.diaperCount > 0 {
                        dotItem(AppColor.accentDiaper, daycareDiaperWords)
                    }
                    if daycare.napSeconds + liveNapSeconds > 0 {
                        dotItem(AppColor.accentSleep,
                                TimeFormatting.duration(minutes: Int((daycare.napSeconds + liveNapSeconds) / 60)))
                    }
                    // Photos only — activities live on the timeline; the
                    // recap keeps its one-line promise.
                    if daycare.photoCount > 0 {
                        dotItem(AppColor.text3, Plural.count(daycare.photoCount, "photo"))
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

    private func dotItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text)
                .font(.caption)
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
                .font(.system(size: 11, weight: .semibold))
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
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColor.text)
                .frame(width: 52, alignment: .leading)
            Text(text)
                .font(.caption)
                .foregroundStyle(textTint)
                .monospacedDigit()
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
    }

    private var accessibilitySummary: String {
        var parts = ["\(babyName) is at daycare since \(TimeFormatting.clock(since))"]
        if napping, let start = liveNapStartedAt {
            parts.append("napping right now, \(TimeFormatting.duration(from: start, to: now)) so far")
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
        parts.append("at daycare: " + (recap.isEmpty ? "nothing yet" : recap.joined(separator: ", ")))
        if daycare.medicationCount > 0 {
            parts.append("\(Plural.count(daycare.medicationCount, "medication")) given, see the timeline")
        }
        return parts.joined(separator: ", ")
    }
}

/// The day as a horizontal time strip: a soft track spanning the waking
/// day, the daycare window tinted teal from drop-off and fading toward
/// "now" (the day is still being written), naps as slim lavender lozenges
/// in the band, feeds as teal dots above it, diapers as amber dots below,
/// sparse hour labels underneath. A running Brightwheel nap runs its
/// lozenge into a glow dot at the now edge, breathing while he sleeps.
private struct DayFlowStrip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let marks: [RibbonMark]
    /// When the daycare day began — the tinted zone's left edge.
    let since: Date
    /// Start of a Brightwheel nap still running.
    let liveNapStartedAt: Date?
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
                    // Track
                    let band = CGRect(x: 0, y: bandY, width: size.width, height: bandH)
                    ctx.fill(Path(roundedRect: band, cornerRadius: bandH / 2),
                             with: .color(AppColor.card2.opacity(0.8)))

                    // Daycare zone, drop-off → now, soft right edge. A place,
                    // not an event — so a neutral wash, NOT a palette color:
                    // teal here read as feed territory under the feed dots.
                    // Daycare's teal identity stays in the glyph and chrome.
                    let zone = CGRect(x: x(hour(since)), y: bandY,
                                      width: max(bandH, nowX - x(hour(since))), height: bandH)
                    ctx.fill(Path(roundedRect: zone, cornerRadius: bandH / 2),
                             with: .linearGradient(
                                Gradient(colors: [AppColor.text2.opacity(0.16),
                                                  AppColor.text2.opacity(0.05)]),
                                startPoint: CGPoint(x: zone.minX, y: 0),
                                endPoint: CGPoint(x: zone.maxX, y: 0)))
                    let glyph = ctx.resolve(Text(Image(systemName: "building.2.fill"))
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(AppColor.text2))
                    ctx.draw(glyph, at: CGPoint(x: zone.minX + 8, y: zone.midY), anchor: .center)

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

                    // Feeds above, diapers below
                    func dot(_ h: Double, _ color: Color, above: Bool) {
                        let y = above ? bandY - 7 : bandY + bandH + 7
                        ctx.fill(Path(ellipseIn: CGRect(x: x(h) - 3.2, y: y - 3.2,
                                                        width: 6.4, height: 6.4)),
                                 with: .color(color))
                    }
                    for mark in marks where mark.kind == .feed {
                        dot(hour(mark.start), AppColor.accentFeed, above: true)
                    }
                    for mark in marks where mark.kind == .diaper {
                        dot(hour(mark.start), AppColor.accentDiaper, above: false)
                    }

                    // The "now" edge, marked even outside a nap
                    if liveNapStartedAt == nil {
                        ctx.stroke(
                            Path(ellipseIn: CGRect(x: nowX - 3, y: bandY + bandH / 2 - 3,
                                                   width: 6, height: 6)),
                            with: .color(AppColor.text2), lineWidth: 1.5)
                    }

                    // Sparse hour labels
                    var h = ceil(window.start)
                    while h.truncatingRemainder(dividingBy: 3) != 0 { h += 1 }
                    while h <= window.end {
                        let t = ctx.resolve(Text(hourLabel(Int(h)))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(AppColor.text3))
                        ctx.draw(t, at: CGPoint(x: min(max(x(h), 7), size.width - 9),
                                                y: size.height - 4), anchor: .center)
                        h += 3
                    }
                }

                // The living part: a breathing glow where the nap meets now.
                if liveNapStartedAt != nil {
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

    /// The waking-day window: starts at 6 AM or the day's first meaningful
    /// moment (an overnight sleep counts by its END — when he woke — so the
    /// strip never stretches back to midnight), ends at 6 PM or just past now.
    private func hourWindow(dayStart: Date) -> (start: Double, end: Double) {
        func hour(_ d: Date) -> Double { d.timeIntervalSince(dayStart) / 3600 }
        let moments = marks.map { mark in
            mark.kind == .sleep && hour(mark.start) <= 0.01
                ? hour(mark.end ?? now) : hour(mark.start)
        }
        let start = min(6, floor(moments.min() ?? 6))
        let end = max(18, min(24, hour(now) + 0.75))
        return (max(0, start), end)
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

/// The "save all" capsule both daycare card forms share — parents want the
/// day's photos in the camera roll without tapping each one.
struct SavePhotosButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                Text(count == 1 ? "Save photo to camera roll"
                                : "Save all \(count) photos to camera roll")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(colorScheme == .dark ? AppColor.accentCheck
                                                  : Color(hex: "1A7E8F"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(AppColor.accentCheck.opacity(0.13), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - The finished day (after pickup)

/// The quiet form, shown after checkout in the old report card's position:
/// the daycare slice of the day with its attendance span. The TODAY card is
/// back above by then, so this stays daycare-only and calm.
struct DaycareCard: View {
    let babyName: String
    let day: DaycareDaySummary
    /// Batch-saves the day's daycare photos (HomeView owns the events and
    /// the toast). Nil hides the affordance.
    var onSavePhotos: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\u{1F3EB}").font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(babyName)'s day at daycare")
                        .font(.headline)
                        .foregroundStyle(AppColor.text)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(AppColor.text2)
                            .monospacedDigit()
                    }
                }
            }
            Text(summaryLine)
                .font(.subheadline)
                .foregroundStyle(AppColor.text)
                .fixedSize(horizontal: false, vertical: true)
            if let extras {
                Text(extras)
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
            }
            if day.medicationCount > 0 {
                Text("\(Plural.count(day.medicationCount, "medication")) given — see the timeline.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColor.accentMedication)
            }
            if let onSavePhotos, day.photoCount > 0 {
                SavePhotosButton(count: day.photoCount, action: onSavePhotos)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .surfaceCard(cornerRadius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if let onSavePhotos, day.photoCount > 0 {
                Button("Save daycare photos to camera roll", action: onSavePhotos)
            }
        }
        .accessibilityIdentifier("daycareCard")
    }

    private var subtitle: String? {
        guard let checkIn = day.checkIn else { return nil }
        guard let checkOut = day.checkOut, checkOut > checkIn else {
            return "from \(TimeFormatting.clock(checkIn))"
        }
        return "\(TimeFormatting.clock(checkIn)) – \(TimeFormatting.clock(checkOut))"
            + " · \(TimeFormatting.duration(from: checkIn, to: checkOut))"
    }

    private var summaryLine: String {
        var parts: [String] = []
        if day.feedCount > 0 {
            parts.append("\(Plural.count(day.feedCount, "bottle")) (\(OzFormat.string(day.feedOz)) oz)")
        }
        if day.napCount > 0 {
            parts.append("\(Plural.count(day.napCount, "nap")) (\(TimeFormatting.duration(minutes: Int(day.napSeconds / 60))))")
        }
        if day.diaperCount > 0 { parts.append(Plural.count(day.diaperCount, "diaper change")) }
        guard !parts.isEmpty else { return "A quiet day at daycare." }
        return "\(babyName) had " + parts.formatted(.list(type: .and)) + "."
    }

    private var extras: String? {
        var parts: [String] = []
        if day.activityCount > 0 {
            parts.append("\(day.activityCount) " + (day.activityCount == 1 ? "activity" : "activities"))
        }
        if day.photoCount > 0 { parts.append(Plural.count(day.photoCount, "photo")) }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ") + " on the timeline"
    }
}

#Preview("Hero, napping") {
    DaycareDayHeroCard(
        babyName: "Miller",
        marks: {
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
        }(),
        feedCount: 3, feedOz: 7, diaperCount: 3, wetCount: 2, dirtyCount: 1,
        sleepSeconds: 4 * 3600 + 50 * 60,
        daycare: {
            var d = DaycareDaySummary()
            d.feedCount = 1; d.feedOz = 2; d.diaperCount = 1
            d.wetCount = 1
            d.napCount = 1; d.napSeconds = 40 * 60
            d.activityCount = 2; d.photoCount = 3
            return d
        }(),
        since: .now.addingTimeInterval(-69 * 60),
        liveNapStartedAt: .now.addingTimeInterval(-12 * 60),
        now: .now
    )
    .padding()
    .background(AppColor.bg)
    .preferredColorScheme(.dark)
}
