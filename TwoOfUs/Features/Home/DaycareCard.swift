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
/// numbers in two formats. Three composition rings carry the whole-day
/// totals, each ring split into a deeper home arc and a lighter daycare arc
/// so the where-he-was story is geometry, not a table. Mid-nap the sleep
/// ring breathes under a lavender glow and its total ticks live. Two quiet
/// rows underneath give the exact home/daycare numbers for the parent who
/// wants them. Checkout dissolves it back into the plain TODAY card plus
/// the quiet finished-day card below.
struct DaycareDayHeroCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let babyName: String
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

    // The home side of the split is the day minus the daycare slice.
    private var homeOz: Double { max(0, feedOz - daycare.feedOz) }
    private var homeFeeds: Int { max(0, feedCount - daycare.feedCount) }
    private var homeDiapers: Int { max(0, diaperCount - daycare.diaperCount) }
    private var homeWet: Int { max(0, wetCount - daycare.wetCount) }
    private var homeDirty: Int { max(0, dirtyCount - daycare.dirtyCount) }
    private var homeSleep: TimeInterval { max(0, sleepSeconds - daycare.napSeconds) }
    private var sleepTotal: TimeInterval { sleepSeconds + liveNapSeconds }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(babyName)'s Day")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(AppColor.text)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text("daycare since \(TimeFormatting.clock(since))")
                        .monospacedDigit()
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(checkInk)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(AppColor.accentCheck.opacity(0.13), in: Capsule())
            }

            // The day's totals as three composition rings — the deeper arc is
            // the home share, the lighter arc the daycare share.
            HStack(alignment: .top, spacing: 0) {
                if showFeed {
                    statColumn(.feed, color: AppColor.accentFeed,
                               homeFraction: homeShare(home: homeOz, total: feedOz,
                                                       fallbackHome: Double(homeFeeds),
                                                       fallbackTotal: Double(feedCount)),
                               active: feedCount > 0,
                               value: feedCount > 0 ? OzFormat.string(feedOz) : "—",
                               unit: feedCount > 0 ? "oz" : nil,
                               caption: feedCount > 0 ? Plural.count(feedCount, "feed") : "no feeds yet")
                }
                if showDiaper {
                    statColumn(.diaper, color: AppColor.accentDiaper,
                               homeFraction: homeShare(home: Double(homeDiapers),
                                                       total: Double(diaperCount)),
                               active: diaperCount > 0,
                               value: diaperCount > 0 ? "\(diaperCount)" : "—",
                               unit: nil,
                               caption: diaperCaption)
                }
                if showSleep {
                    statColumn(.sleep, color: AppColor.accentSleep,
                               homeFraction: homeShare(home: homeSleep, total: sleepTotal),
                               active: napping || sleepSeconds > 0,
                               value: sleepValue,
                               unit: nil,
                               caption: "sleep",
                               liveNap: napping)
                }
            }

            // The exact numbers, two quiet rows — scannable without reading.
            VStack(alignment: .leading, spacing: 7) {
                splitRow(systemImage: "house.fill", tint: AppColor.text2,
                         title: "Home", lines: homeLines)
                splitRow(systemImage: "building.2.fill", tint: checkInk,
                         title: "Daycare", lines: daycareLines)
                if daycare.medicationCount > 0 {
                    splitRow(systemImage: "pills.fill", tint: AppColor.accentMedication,
                             title: "Meds",
                             text: "\(Plural.count(daycare.medicationCount, "medication")) — see timeline",
                             textTint: AppColor.accentMedication)
                }
            }
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

    // MARK: Rings

    private static let ringSize: CGFloat = 86
    private static let ringLine: CGFloat = 9

    private func statColumn(_ stat: Stat, color: Color, homeFraction: Double,
                            active: Bool, value: String, unit: String?,
                            caption: String, liveNap: Bool = false) -> some View {
        VStack(spacing: 8) {
            ZStack {
                // The nap's breath: a soft lavender glow swelling and settling
                // behind the sleep ring, slow as sleeping lungs.
                if liveNap && !reduceMotion {
                    Circle()
                        .fill(color.opacity(0.30))
                        .frame(width: Self.ringSize, height: Self.ringSize)
                        .blur(radius: 14)
                        .scaleEffect(breathing ? 1.22 : 0.88)
                        .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true),
                                   value: breathing)
                        .onAppear { breathing = true }
                        .onDisappear { breathing = false }
                }
                if liveNap {
                    Circle()
                        .fill(color.opacity(0.10))
                        .frame(width: Self.ringSize - Self.ringLine,
                               height: Self.ringSize - Self.ringLine)
                }
                CompositionRing(color: color, homeFraction: homeFraction,
                                active: active, lineWidth: Self.ringLine,
                                appearDelay: appearDelay(for: stat))
                    .frame(width: Self.ringSize, height: Self.ringSize)
                VStack(spacing: unit == nil ? 0 : -1) {
                    Text(value)
                        // Ink in the ring's own family, not stark black — the
                        // number should feel dyed into the pastel.
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(active ? ink(for: stat) : AppColor.text3)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .padding(.horizontal, 12)
                    if let unit {
                        Text(unit)
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(active ? ink(for: stat).opacity(0.7) : AppColor.text3)
                    }
                }
                .frame(width: Self.ringSize, height: Self.ringSize)
            }
            .scaleEffect(popped.contains(stat) ? 1.1 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.55),
                       value: popped)

            if liveNap, let start = liveNapStartedAt {
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

    private func appearDelay(for stat: Stat) -> Double {
        switch stat {
        case .feed: 0
        case .diaper: 0.12
        case .sleep: 0.24
        }
    }

    /// The home share of a metric's ring, clamped so a real-but-small side
    /// stays a visible sliver. When the primary measure is empty (feeds
    /// logged with no amounts), the count fallback keeps the split honest.
    private func homeShare(home: Double, total: Double,
                           fallbackHome: Double = 0, fallbackTotal: Double = 0) -> Double {
        var h = home, t = total
        if t <= 0 { h = fallbackHome; t = fallbackTotal }
        guard t > 0 else { return 1 }
        let f = h / t
        if f <= 0 { return 0 }
        if f >= 1 { return 1 }
        return min(max(f, 0.08), 0.92)
    }

    private var diaperCaption: String {
        guard diaperCount > 0 else { return "changes" }
        var parts: [String] = []
        if wetCount > 0 { parts.append("\(wetCount) wet") }
        if dirtyCount > 0 { parts.append("\(dirtyCount) dirty") }
        return parts.isEmpty ? Plural.count(diaperCount, "change")
                             : parts.joined(separator: " · ")
    }

    /// `accentCheck` is too pale for text on the light card — a deeper sibling
    /// in light mode, the accent itself in dark.
    private var checkInk: Color {
        colorScheme == .dark ? AppColor.accentCheck : Color(hex: "1A7E8F")
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

    // MARK: Home / daycare split

    /// One emoji-tagged line in a split column — "🍼 10 oz (2)". `spoken` is
    /// the VoiceOver spelling where the visual leans on emoji ("💧1 💩1" →
    /// "1 wet, 1 dirty").
    private struct SplitLine: Identifiable {
        let emoji: String
        let text: String
        var tint: Color?
        var spoken: String?
        var id: String { emoji + text }
    }

    private var homeLines: [SplitLine] {
        trackerLines(oz: homeOz, feeds: homeFeeds, wet: homeWet, dirty: homeDirty,
                     sleep: homeSleep)
    }

    /// The daycare row also carries the day's softer entries — activities,
    /// photos. A running nap counts live, matching the ring above.
    /// (Medication gets its own red row; it shouldn't hide mid-list.)
    private var daycareLines: [SplitLine] {
        var lines = trackerLines(oz: daycare.feedOz, feeds: daycare.feedCount,
                                 wet: daycare.wetCount, dirty: daycare.dirtyCount,
                                 sleep: daycare.napSeconds + liveNapSeconds)
        if daycare.activityCount > 0 {
            lines.append(SplitLine(
                emoji: "🎨",
                text: "\(daycare.activityCount) " + (daycare.activityCount == 1 ? "activity" : "activities")))
        }
        if daycare.photoCount > 0 {
            lines.append(SplitLine(emoji: "📸", text: Plural.count(daycare.photoCount, "photo")))
        }
        return lines
    }

    private func trackerLines(oz: Double, feeds: Int, wet: Int, dirty: Int,
                              sleep: TimeInterval) -> [SplitLine] {
        var lines: [SplitLine] = []
        if showFeed, feeds > 0 {
            let text = oz > 0 ? "\(OzFormat.string(oz)) oz (\(feeds))" : "\(feeds)"
            lines.append(SplitLine(emoji: "🍼", text: text,
                                   spoken: "\(OzFormat.string(oz)) ounces across \(Plural.count(feeds, "feed"))"))
        }
        if showDiaper, wet + dirty > 0 {
            // Wet vs dirty, the split parents and pediatricians actually
            // count — "💧1 💩1". A .both diaper tallies on each side.
            var spoken: [String] = []
            if wet > 0 { spoken.append("\(wet) wet") }
            if dirty > 0 { spoken.append("\(dirty) dirty") }
            lines.append(SplitLine(emoji: wet > 0 ? "💧" : "💩",
                                   text: diaperText(wet: wet, dirty: dirty),
                                   spoken: spoken.joined(separator: ", ") + " diapers"))
        }
        if showSleep, sleep > 0 {
            lines.append(SplitLine(emoji: "💤",
                                   text: TimeFormatting.duration(minutes: Int(sleep / 60)),
                                   spoken: "\(TimeFormatting.duration(minutes: Int(sleep / 60))) sleep"))
        }
        return lines
    }

    /// "1 💩1" after a 💧 lead emoji, or just the counts when one side is
    /// zero — the emoji column renders the first glyph, this the remainder.
    private func diaperText(wet: Int, dirty: Int) -> String {
        if wet > 0 && dirty > 0 { return "\(wet)  💩\(dirty)" }
        return wet > 0 ? "\(wet)" : "\(dirty)"
    }

    private func splitRow(systemImage: String, tint: Color, title: String,
                          lines: [SplitLine]) -> some View {
        // Each item is glued with non-breaking spaces so a long row wraps
        // between items, never inside "1 activity".
        splitRow(systemImage: systemImage, tint: tint, title: title,
                 text: lines.isEmpty ? "nothing yet"
                     : lines.map { "\($0.emoji)\u{00A0}\($0.text.replacingOccurrences(of: " ", with: "\u{00A0}"))" }
                            .joined(separator: " · "),
                 textTint: lines.isEmpty ? AppColor.text3 : AppColor.text2)
    }

    /// One split row: a small tinted icon disc, a fixed-width title so the
    /// rows' numbers align, and the values on one quiet line.
    private func splitRow(systemImage: String, tint: Color, title: String,
                          text: String, textTint: Color) -> some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.13))
                    .frame(width: 26, height: 26)
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
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
        func speak(_ lines: [SplitLine]) -> String {
            lines.isEmpty ? "nothing yet"
                : lines.map { $0.spoken ?? $0.text }.joined(separator: ", ")
        }
        var parts = ["\(babyName) is at daycare since \(TimeFormatting.clock(since))"]
        if napping, let start = liveNapStartedAt {
            parts.append("napping right now, \(TimeFormatting.duration(from: start, to: now)) so far")
        }
        parts.append("at home: \(speak(homeLines))")
        parts.append("at daycare: \(speak(daycareLines))")
        return parts.joined(separator: ", ")
    }
}

/// One metric's ring: a faint full track, then a deeper arc for the home
/// share and a lighter arc of the same hue for the daycare share, clockwise
/// from 12 o'clock with a soft gap where they meet. One lone side owns the
/// whole circle, seamless.
private struct CompositionRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let color: Color
    let homeFraction: Double   // 0…1 of the metric that happened at home
    let active: Bool
    var lineWidth: CGFloat = 9
    /// Stagger for the draw-in, so the three rings bloom left to right.
    var appearDelay: Double = 0

    /// 0→1 on first appearance: both arcs sweep in together from 12 o'clock,
    /// the little morning ritual of opening the app at your desk.
    @State private var drawn: Double = 0

    /// Trim backed off each seam; with round caps this nets a hairline gap.
    private let gap = 0.025

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.12), lineWidth: lineWidth)
            if active {
                let f = min(max(homeFraction, 0), 1)
                if f >= 0.999 {
                    ring(from: 0, to: drawn, opacity: 1)
                } else if f <= 0.001 {
                    ring(from: 0, to: drawn, opacity: 0.38)
                } else {
                    ring(from: gap, to: min(f - gap, drawn), opacity: 1)
                    if drawn > f + gap {
                        ring(from: f + gap, to: min(1 - gap, drawn), opacity: 0.38)
                    }
                }
            }
        }
        // New events re-balance the arcs with a settle; the draw-in itself is
        // driven by `drawn`'s own withAnimation so the stagger survives.
        .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8),
                   value: homeFraction)
        .onAppear {
            if reduceMotion {
                drawn = 1
            } else {
                withAnimation(.easeOut(duration: 0.9).delay(appearDelay)) { drawn = 1 }
            }
        }
    }

    private func ring(from: Double, to: Double, opacity: Double) -> some View {
        Circle()
            .trim(from: from, to: max(from, to))
            .stroke(color.opacity(opacity),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
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
