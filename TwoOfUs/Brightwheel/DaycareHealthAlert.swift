import Foundation

/// Decides which daycare entries are health news a parent must not miss —
/// a fever call, a "please pick him up", an incident report. Pure and
/// unit-tested; the importer and the sync path (co-parent's phone) both ask
/// it, so both phones agree on what alerts loudly.
///
/// Deliberately generous: a false alarm costs a glance, a missed fever call
/// costs a sick baby sitting at daycare. Infant-normal vocabulary ("spit
/// up", "fell asleep") is excluded so the everyday pings stay quiet.
enum DaycareHealthAlert {
    /// At or above this, a temperature reading alerts on its own (°F).
    /// 100.4 is the usual pediatric fever line; daycares often send home at
    /// 100.4–100.5, and a low-grade 99.5+ is worth the heads-up.
    static let temperatureThreshold = 99.5

    private static let patterns: [Regex<AnyRegexOutput>] = [
        #"\bfever(ish|s)?\b"#,
        #"\btemp(erature)?s?\b"#,
        #"\bsen[dt]\s+(\w+\s+){0,2}home\b"#,          // "send him home", "sent home"
        #"\bpick\s+(him|her|them|\w+)\s+up\b"#,         // "pick him up", "pick Miller up"
        #"\bpick[- ]?up\s+(early|soon|asap|now)\b"#,
        #"\bcome\s+(get|pick)\b"#,
        #"\bvomit\w*"#, #"\bthrew\s+up\b"#, #"\bthrowing\s+up\b"#,
        #"\bdiarrh?ea\b"#,
        #"\brash(es)?\b"#, #"\bhives\b"#, #"\ballergic\b"#, #"\breaction\b"#, #"\bswelling\b"#,
        #"\bsick\b"#, #"\bill\b"#, #"\bnot\s+(feeling|acting)\s+(well|himself|herself|like)\b"#,
        #"\blethargic\b"#, #"\bwheez\w*"#, #"\b(trouble|difficulty)\s+breathing\b"#,
        #"\bpink\s*eye\b"#, #"\bconjunctivitis\b"#, #"\bear\s+infection\b"#,
        #"\binjur\w*"#, #"\bincident\b"#, #"\bbump(ed)?\b"#,
        #"\bbit(ten)?\s+by\b"#, #"\bbiting\b"#,
        #"\bbleed\w*"#, #"\bhit\s+(his|her|their)\s+head\b"#, #"\bfell\s+(down|off|over)\b"#,
        #"\b(tylenol|motrin|ibuprofen|acetaminophen)\b"#,
    ].map { try! Regex($0) }

    /// Whether free text (a message, a staff note, a health-check note)
    /// carries health news.
    static func isConcerning(_ text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        let lower = text.lowercased()
        if patterns.contains(where: { lower.contains($0) }) { return true }
        if let reading = highestTemperature(in: lower), reading >= temperatureThreshold { return true }
        return false
    }

    /// Whether a logged health check needs a loud alert: a reading at or over
    /// the threshold, or a note that says something worrying.
    static func isConcerning(type: HealthCheckType, value: Double, notes: String?) -> Bool {
        if type == .temperature, value >= temperatureThreshold { return true }
        return isConcerning(notes)
    }

    /// A short label for the Today card's Health row — "Fever", "Pick-up
    /// request", "Rash or reaction". Nil when the text isn't health news.
    /// Never quotes a number from free text: "100.5 is our cut off" is a
    /// threshold, not his temperature — logged health checks carry the
    /// real reading.
    static func headline(for text: String?) -> String? {
        guard let text, isConcerning(text) else { return nil }
        let lower = text.lowercased()
        func has(_ pattern: String) -> Bool { (try? Regex(pattern)).map { lower.contains($0) } ?? false }
        if has(#"\bfever"#) || has(#"\btemp"#)
            || (highestTemperature(in: lower) ?? 0) >= temperatureThreshold { return "Fever" }
        if has(#"\bsen[dt]\s+(\w+\s+){0,2}home\b|\bpick\s+\w+\s+up\b|\bpick[- ]?up\s+(early|soon|asap|now)\b|\bcome\s+(get|pick)\b"#) { return "Pick-up request" }
        if has(#"\bvomit|\bthrew\s+up|\bthrowing\s+up"#) { return "Vomiting" }
        if has(#"\bdiarrh?ea"#) { return "Diarrhea" }
        if has(#"\brash|\bhives|\ballergic|\breaction|\bswelling"#) { return "Rash or reaction" }
        if has(#"\binjur|\bincident|\bbump|\bbit(ten)?\s+by|\bbiting|\bbleed|\bhit\s+\w+\s+head|\bfell\s+(down|off|over)"#) { return "Incident" }
        return "Not feeling well"
    }

    /// The highest plausible body temperature written in the text — "99.9",
    /// "100.5°", "101 F". Only decimals or explicit degree marks count, so a
    /// "100 days" or "4 oz" never trips it.
    static func highestTemperature(in text: String) -> Double? {
        let readings = text.matches(of: /\b(9[5-9]|10[0-7])(\.[0-9])?\s*(°|degrees?|f\b)?/)
            .compactMap { match -> Double? in
                let hasDecimal = match.output.2 != nil
                let hasUnit = match.output.3 != nil
                guard hasDecimal || hasUnit else { return nil }
                return Double(match.output.1 + (match.output.2 ?? ""))
            }
        return readings.max()
    }
}

extension StaffNoteEvent {
    /// A daycare note or message that reads as health news (fever, pick-up
    /// request, incident) — styled red with a 🌡️ on the timeline. Computed
    /// from the text, so no stored field or schema change. (Lives here, not
    /// on the model, because the model file is shared with the extensions.)
    var isHealthNews: Bool { isFromDaycare && !isAnnouncement && DaycareHealthAlert.isConcerning(text) }

    /// A Brightwheel chat message (vs. an `ac_note` activity).
    var isDaycareMessage: Bool { externalID?.hasPrefix("msg-") == true }

    /// A center-wide Brightwheel broadcast — collapses to one line.
    var isAnnouncement: Bool { externalID?.hasPrefix("msg-b-") == true }

    /// Whether this note is evidence he's AT daycare — the stand-in check-in
    /// / check-out on marker-less days. Chat messages aren't: staff message
    /// from the center whether or not he's there yet ("Will Miller be joining
    /// us today?" at 9:01 on a late doctor's-appointment morning), and
    /// announcements go out center-wide. `ac_note` activities are.
    var countsTowardAttendance: Bool { isFromDaycare && !isDaycareMessage }

    /// The Brightwheel message's own `object_id` (the external id minus its
    /// "msg-"/"msg-b-" tag) — what its imported photos are keyed under.
    var brightwheelMessageID: String? {
        guard let id = externalID else { return nil }
        for prefix in ["msg-b-", "msg-"] where id.hasPrefix(prefix) {
            let rest = String(id.dropFirst(prefix.count))
            return rest.isEmpty ? nil : rest
        }
        return nil
    }

    /// This message's attached photos/videos, picked out of `media` (any
    /// order), oldest first so they read in the order they were attached.
    func attachedPhotos(in media: [MediaEvent]) -> [MediaEvent] {
        guard let messageID = brightwheelMessageID else { return [] }
        let prefix = BrightwheelImporter.messagePhotoPrefix(messageID)
        return media
            .filter { $0.deletedAt == nil && $0.externalID?.hasPrefix(prefix) == true }
            .sorted { ($0.externalID ?? "").localizedStandardCompare($1.externalID ?? "") == .orderedAscending }
    }

    /// The announcement's headline: its first line, minus decorative emoji,
    /// and out of ALL CAPS — "🍂 BOARD BOOK OF THE MONTH 🍂" → "Board Book
    /// of the Month".
    var announcementTitle: String {
        StaffNoteEvent.headline(from: text)
    }

    static func headline(from text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        var line = firstLine.unicodeScalars
            .filter { !($0.properties.isEmojiPresentation || $0.properties.isEmoji && $0.value > 0x2000) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters.subtracting(CharacterSet(charactersIn: "!?"))))
        let letters = line.filter(\.isLetter)
        if !letters.isEmpty, letters.allSatisfy(\.isUppercase) {
            let small: Set<String> = ["a", "an", "and", "at", "for", "in", "of", "on", "or", "the", "to"]
            line = line.lowercased().split(separator: " ").enumerated().map { i, word in
                i > 0 && small.contains(String(word)) ? String(word) : word.prefix(1).uppercased() + word.dropFirst()
            }.joined(separator: " ")
        }
        if line.count > 60 { line = String(line.prefix(57)).trimmingCharacters(in: .whitespaces) + "…" }
        return line.isEmpty ? "Announcement" : line
    }
}

extension MediaEvent {
    /// Whether this photo/video is evidence he's AT daycare. A photo attached
    /// to a chat message isn't (same reasoning as
    /// `StaffNoteEvent.countsTowardAttendance`); an activity photo is.
    var countsTowardAttendance: Bool {
        isFromDaycare && externalID?.hasPrefix("msg-") != true
    }
}
