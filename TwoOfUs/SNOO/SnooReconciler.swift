import Foundation

/// A local sleep record reduced to its span — the only thing reconciliation
/// needs, so tests never touch SwiftData.
struct LocalSleepSpan: Hashable, Sendable {
    let startedAt: Date
    let endedAt: Date?          // nil == timer still running

    init(startedAt: Date, endedAt: Date?) {
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    init(_ event: SleepEvent) {
        self.init(startedAt: event.startedAt, endedAt: event.endedAt)
    }
}

/// Pure reconciliation: (SNOO sessions, local sleep, sync state) → suggestions.
/// No I/O, no clocks — `now` is a parameter. All the interesting logic and all
/// the unit tests live here (§4).
enum SnooReconciler {
    /// A SNOO session covered more than this much by local sleep is considered
    /// already logged (§7, filter 4).
    static let overlapThreshold = 0.5
    /// In-progress sessions older than this are stale — likely a missed
    /// end-of-session on the SNOO side (§7, filter 6).
    static let inProgressMaxAge: TimeInterval = 14 * 3600
    static let minimumDuration: TimeInterval = 5 * 60

    static func suggestions(
        snooSessions: [SnooSession],
        localSleeps: [LocalSleepSpan],
        importedIDs: Set<String>,
        dismissedIDs: Set<String>,
        now: Date
    ) -> [SnooSuggestion] {
        let hasOpenLocalSleep = localSleeps.contains { $0.endedAt == nil }

        return snooSessions
            .filter { session in
                if importedIDs.contains(session.id) { return false }      // 1
                if dismissedIDs.contains(session.id) { return false }     // 2
                if let duration = session.duration,
                   duration < minimumDuration { return false }            // 3
                if maxOverlapFraction(of: session, in: localSleeps, now: now)
                    > overlapThreshold { return false }                   // 4
                if session.isInProgress {
                    if hasOpenLocalSleep { return false }                 // 5
                    if now.timeIntervalSince(session.startedAt)
                        > inProgressMaxAge { return false }               // 6
                    // Guard the pathological clock-skew case: an in-progress
                    // session "from the future" can't be backdated sanely.
                    if session.startedAt > now { return false }
                }
                return true
            }
            .sorted { $0.startedAt > $1.startedAt }
            .map { session in
                SnooSuggestion(
                    id: session.id,
                    startedAt: session.startedAt,
                    kind: session.endedAt.map { .completed(endedAt: $0) } ?? .inProgress
                )
            }
    }

    /// Fraction of the SNOO session's span covered by the single local sleep
    /// that overlaps it most (§7 overlap test). Open intervals (SNOO still
    /// running, or a running local timer) are closed at `now`.
    static func maxOverlapFraction(
        of session: SnooSession,
        in localSleeps: [LocalSleepSpan],
        now: Date
    ) -> Double {
        let start = session.startedAt
        let end = session.endedAt ?? now
        let length = end.timeIntervalSince(start)
        guard length > 0 else { return 1 }   // zero-length: treat as covered

        return localSleeps.reduce(0) { best, local in
            let localEnd = local.endedAt ?? now
            let overlap = min(end, localEnd).timeIntervalSince(max(start, local.startedAt))
            return max(best, max(0, overlap) / length)
        }
    }
}
