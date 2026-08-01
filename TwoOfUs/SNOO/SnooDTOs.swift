import Foundation

// Wire-format types for the unofficial API. Every field is optional (§9:
// schema drift is expected — only startTime is truly required downstream) and
// unknown enum strings decode to nil rather than failing the whole payload.
// Shapes documented in docs/SNOO-API.md, from community-client fixtures.

/// Cognito InitiateAuth response (login and refresh share it). Cognito's JSON
/// is PascalCase.
struct CognitoAuthResponseDTO: Decodable {
    struct AuthenticationResultDTO: Decodable {
        let AccessToken: String?
        let IdToken: String?
        let RefreshToken: String?
        let ExpiresIn: TimeInterval?
    }
    let AuthenticationResult: AuthenticationResultDTO?
}

/// GET /hds/me/v11/devices — an object whose "snoo" key lists the devices.
struct SnooDeviceListDTO: Decodable {
    let snoo: [SnooDeviceDTO]?
}

struct SnooDeviceDTO: Decodable {
    let serialNumber: String?
    let babyIds: [String]?
}

/// GET /us/me/v10/babies — array of babies; `_id` is the id other URLs want.
struct SnooBabyDTO: Decodable {
    let _id: String?
}

/// GET …/sessions/last — the current or most recent session.
/// "Still running" == endTime absent/null.
struct SnooLastSessionDTO: Decodable {
    let startTime: String?
    let endTime: String?
    let levels: [SnooLastSessionLevelDTO]?
}

struct SnooLastSessionLevelDTO: Decodable {
    let level: String?
}

/// One segment in the aggregated day view: `type` "asleep"/"soothing"/"awake",
/// `stateDuration` in seconds, `startTime` local with no offset.
struct SnooLevelEntryDTO: Decodable {
    let sessionId: String?
    let type: String?
    let startTime: String?
    let stateDuration: TimeInterval?
    let isActive: Bool?
}

/// GET …/sessions/aggregated/?startTime=… — one day of history. The segment
/// array has been seen as `levels` (rado0x54 fixture) and `detailedLevels`
/// (pysnooapi query flag) — accept either.
struct SnooAggregatedDayDTO: Decodable {
    let levels: [SnooLevelEntryDTO]?
    let detailedLevels: [SnooLevelEntryDTO]?

    var entries: [SnooLevelEntryDTO] { detailedLevels ?? levels ?? [] }
}

/// Timestamp parsing for the wire formats seen across community clients:
/// ISO8601 Z with milliseconds (last-session), bare local "YYYY-MM-DD
/// HH:MM:SS.mmm" (aggregated), and epoch seconds/milliseconds just in case.
enum SnooDates {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()

    /// Aggregated timestamps carry no zone — the server renders them in the
    /// account's configured timezone, which for this household is the device
    /// zone. Parsed as local so cards match what the SNOO app shows.
    private static func bareFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
    private static let bareSpaceMillis = bareFormatter("yyyy-MM-dd HH:mm:ss.SSS")
    private static let bareSpace = bareFormatter("yyyy-MM-dd HH:mm:ss")
    private static let bareTMillis = bareFormatter("yyyy-MM-dd'T'HH:mm:ss.SSS")
    private static let bareT = bareFormatter("yyyy-MM-dd'T'HH:mm:ss")

    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let d = isoFractional.date(from: raw) ?? iso.date(from: raw) { return d }
        if let d = bareSpaceMillis.date(from: raw) ?? bareSpace.date(from: raw)
            ?? bareTMillis.date(from: raw) ?? bareT.date(from: raw) { return d }
        if let ms = Double(raw), ms > 1_000_000_000_000 { return Date(timeIntervalSince1970: ms / 1000) }
        if let s = Double(raw), s > 1_000_000_000 { return Date(timeIntervalSince1970: s) }
        return nil
    }

    /// Aggregated query format: "%Y-%m-%d %H:%M:%S.%f" truncated to ms,
    /// local time, no zone (rado0x54/pysnoo `snoo.py`).
    static func queryString(from date: Date) -> String {
        bareSpaceMillis.string(from: date)
    }
}

/// Pure DTO → `SnooSession` conversion. No I/O, fully unit-testable.
enum SnooSessionNormaliser {
    /// Sessions shorter than this are treated as noise and dropped (§7).
    static let minimumDuration: TimeInterval = 5 * 60

    static func session(fromLast dto: SnooLastSessionDTO) -> SnooSession? {
        guard let start = SnooDates.parse(dto.startTime) else { return nil }
        let end = SnooDates.parse(dto.endTime)
        // A completed blip shorter than the floor is noise; an in-progress
        // session is kept regardless (its duration isn't known yet).
        if let end, end.timeIntervalSince(start) < minimumDuration { return nil }
        return SnooSession(
            id: SnooSession.synthesisedID(startedAt: start),
            startedAt: start,
            endedAt: end,
            levels: (dto.levels ?? []).compactMap { $0.level.flatMap(SnooLevel.init(rawValue:)) }
        )
    }

    /// Flattens a day of history into sessions. Segments of one bassinet
    /// session share a `sessionId` (asleep/soothing interleave as the baby
    /// stirs — verified live 2026-07-31), so they coalesce into one span:
    /// first segment start to last segment end, the same start→end semantics
    /// `sessions/last` reports. Only spans containing sleep count, and a
    /// span with an `isActive` segment is still running — surfaced open-ended.
    static func sessions(fromAggregated dto: SnooAggregatedDayDTO) -> [SnooSession] {
        struct Span {
            var start: Date
            var end: Date
            var hasSleep = false
            var isActive = false
        }
        var spans: [String: Span] = [:]
        var loners: [SnooSession] = []
        for entry in dto.entries {
            guard let start = SnooDates.parse(entry.startTime) else { continue }
            let end = start.addingTimeInterval(entry.stateDuration ?? 0)
            let asleep = entry.type?.lowercased() == "asleep"
            let active = entry.isActive ?? false
            guard let id = entry.sessionId else {
                // Nothing to group on — the segment stands alone.
                guard asleep, active || (entry.stateDuration ?? 0) >= minimumDuration
                else { continue }
                loners.append(SnooSession(
                    id: SnooSession.synthesisedID(startedAt: start),
                    startedAt: start,
                    endedAt: active ? nil : end,
                    levels: []
                ))
                continue
            }
            var span = spans[id] ?? Span(start: start, end: end)
            span.start = min(span.start, start)
            span.end = max(span.end, end)
            span.hasSleep = span.hasSleep || asleep
            span.isActive = span.isActive || active
            spans[id] = span
        }
        let grouped = spans.compactMap { id, span -> SnooSession? in
            guard span.hasSleep,
                  span.isActive || span.end.timeIntervalSince(span.start) >= minimumDuration
            else { return nil }
            return SnooSession(id: id, startedAt: span.start,
                               endedAt: span.isActive ? nil : span.end, levels: [])
        }
        return (grouped + loners).sorted { $0.startedAt < $1.startedAt }
    }

    /// Merges the day fetches with the last-session record. A session that
    /// spans a day boundary is clipped into both day windows under the same
    /// id — union those spans back into one. The last-session payload has no
    /// sessionId, so it can only be matched by start instant — an aggregated
    /// session starting within a minute of it is the same session, and last
    /// (the fresher source) wins.
    static func merge(last: SnooSession?, aggregated: [SnooSession]) -> [SnooSession] {
        var byID: [String: SnooSession] = [:]
        var order: [String] = []
        for session in aggregated {
            guard let existing = byID[session.id] else {
                byID[session.id] = session
                order.append(session.id)
                continue
            }
            let end: Date? = if let a = existing.endedAt, let b = session.endedAt {
                max(a, b)
            } else {
                nil    // either half still running → the union is too
            }
            byID[session.id] = SnooSession(
                id: session.id,
                startedAt: min(existing.startedAt, session.startedAt),
                endedAt: end,
                levels: existing.levels.isEmpty ? session.levels : existing.levels
            )
        }
        var result = order.compactMap { byID[$0] }
        if let last {
            result.removeAll { abs($0.startedAt.timeIntervalSince(last.startedAt)) < 60 }
            result.append(last)
        }
        return result.sorted { $0.startedAt > $1.startedAt }
    }
}
