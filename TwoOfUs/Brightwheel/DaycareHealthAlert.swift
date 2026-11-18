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
