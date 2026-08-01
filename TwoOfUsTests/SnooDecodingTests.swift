import XCTest
@testable import TwoOfUs

/// Decoding + normalisation against fixtures shaped like the community-client
/// captures in docs/SNOO-API.md. Also exercises the defensive paths: schema
/// drift (§9 — only startTime is required), unknown enum values, and the
/// dedupe/merge rules.
final class SnooDecodingTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    // MARK: Cognito auth

    func testCognitoLoginResponseDecodes() throws {
        let json = """
        {"AuthenticationResult": {"AccessToken": "at", "IdToken": "idt",
         "RefreshToken": "rt", "ExpiresIn": 3600, "TokenType": "Bearer"},
         "ChallengeParameters": {}}
        """
        let dto = try JSONDecoder().decode(CognitoAuthResponseDTO.self, from: data(json))
        XCTAssertEqual(dto.AuthenticationResult?.IdToken, "idt")
        XCTAssertEqual(dto.AuthenticationResult?.RefreshToken, "rt")
        XCTAssertEqual(dto.AuthenticationResult?.ExpiresIn, 3600)
    }

    func testCognitoRefreshResponseWithoutRefreshTokenDecodes() throws {
        let json = """
        {"AuthenticationResult": {"AccessToken": "at2", "IdToken": "idt2", "ExpiresIn": 3600}}
        """
        let dto = try JSONDecoder().decode(CognitoAuthResponseDTO.self, from: data(json))
        XCTAssertEqual(dto.AuthenticationResult?.IdToken, "idt2")
        XCTAssertNil(dto.AuthenticationResult?.RefreshToken)
    }

    // MARK: Devices

    func testDeviceListDecodes() throws {
        let json = """
        {"snoo": [{"serialNumber": "SN123", "firmwareVersion": "v1.14.12",
                   "babyIds": ["baby-1"], "name": "SNOO",
                   "awsIoT": {"awsRegion": "us-east-1", "thingName": "t"}}]}
        """
        let dto = try JSONDecoder().decode(SnooDeviceListDTO.self, from: data(json))
        XCTAssertEqual(dto.snoo?.first?.serialNumber, "SN123")
        XCTAssertEqual(dto.snoo?.first?.babyIds, ["baby-1"])
    }

    // MARK: Last session (fixture shape: ss_v2_sessions_last__get_200.json)

    func testCompletedLastSessionNormalises() throws {
        let json = """
        {"startTime": "2026-07-25T19:50:06.296Z",
         "endTime": "2026-07-25T21:10:43.025Z",
         "levels": [{"level": "BASELINE"}, {"level": "LEVEL1"}, {"level": "ONLINE"}]}
        """
        let dto = try JSONDecoder().decode(SnooLastSessionDTO.self, from: data(json))
        let session = try XCTUnwrap(SnooSessionNormaliser.session(fromLast: dto))
        XCTAssertFalse(session.isInProgress)
        XCTAssertEqual(session.levels, [.baseline, .level1, .online])
        XCTAssertEqual(session.duration ?? 0, 4836.729, accuracy: 0.01)
    }

    func testRunningLastSessionHasNilEnd() throws {
        let json = """
        {"startTime": "2026-07-25T19:50:06.296Z",
         "levels": [{"level": "BASELINE"}]}
        """
        let dto = try JSONDecoder().decode(SnooLastSessionDTO.self, from: data(json))
        let session = try XCTUnwrap(SnooSessionNormaliser.session(fromLast: dto))
        XCTAssertTrue(session.isInProgress)
    }

    func testLastSessionWithUnknownLevelStillNormalises() throws {
        // Schema drift: a new level string must not sink the session.
        let json = """
        {"startTime": "2026-07-25T19:50:06.296Z",
         "endTime": "2026-07-25T20:50:06.296Z",
         "levels": [{"level": "BASELINE"}, {"level": "SOME_NEW_LEVEL"}]}
        """
        let dto = try JSONDecoder().decode(SnooLastSessionDTO.self, from: data(json))
        let session = try XCTUnwrap(SnooSessionNormaliser.session(fromLast: dto))
        XCTAssertEqual(session.levels, [.baseline])   // unknown value skipped
    }

    func testLastSessionWithoutStartTimeIsNil() throws {
        let dto = try JSONDecoder().decode(SnooLastSessionDTO.self, from: data("{}"))
        XCTAssertNil(SnooSessionNormaliser.session(fromLast: dto))
    }

    func testSubMinimumCompletedLastSessionIsNoise() throws {
        let json = """
        {"startTime": "2026-07-25T19:50:06.296Z", "endTime": "2026-07-25T19:52:06.296Z"}
        """
        let dto = try JSONDecoder().decode(SnooLastSessionDTO.self, from: data(json))
        XCTAssertNil(SnooSessionNormaliser.session(fromLast: dto))
    }

    // MARK: Aggregated day (fixture shape: ss_v2_sessions_aggregated__get_200.json)

    func testAggregatedDayNormalisesAsleepSegmentsOnly() throws {
        let json = """
        {"daySleep": 24536, "nightSleep": 0, "totalSleep": 24536,
         "longestSleep": 8368, "naps": 4, "nightWakings": 0, "timezone": null,
         "levels": [
           {"isActive": false, "sessionId": "1007201535",
            "startTime": "2026-07-25 07:09:10.215", "stateDuration": 8368, "type": "asleep"},
           {"isActive": false, "sessionId": "1198573785",
            "startTime": "2026-07-25 10:43:16.818", "stateDuration": 60, "type": "soothing"},
           {"isActive": false, "sessionId": "1198573786",
            "startTime": "2026-07-25 11:43:16.818", "stateDuration": 3600, "type": "awake"}
         ]}
        """
        let dto = try JSONDecoder().decode(SnooAggregatedDayDTO.self, from: data(json))
        let sessions = SnooSessionNormaliser.sessions(fromAggregated: dto)
        XCTAssertEqual(sessions.count, 1)   // only the "asleep" segment
        XCTAssertEqual(sessions[0].id, "1007201535")
        XCTAssertEqual(sessions[0].duration, 8368)
    }

    func testAggregatedAcceptsDetailedLevelsKey() throws {
        let json = """
        {"detailedLevels": [
           {"sessionId": "9", "startTime": "2026-07-25 13:00:00.000",
            "stateDuration": 3600, "type": "asleep"}]}
        """
        let dto = try JSONDecoder().decode(SnooAggregatedDayDTO.self, from: data(json))
        XCTAssertEqual(SnooSessionNormaliser.sessions(fromAggregated: dto).count, 1)
    }

    func testAggregatedActiveSegmentBecomesInProgress() throws {
        let json = """
        {"levels": [
           {"isActive": true, "sessionId": "42",
            "startTime": "2026-07-25 20:00:00.000", "stateDuration": 120, "type": "asleep"}]}
        """
        let dto = try JSONDecoder().decode(SnooAggregatedDayDTO.self, from: data(json))
        let sessions = SnooSessionNormaliser.sessions(fromAggregated: dto)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertTrue(sessions[0].isInProgress)
    }

    func testAggregatedDropsShortAsleepSegments() throws {
        let json = """
        {"levels": [
           {"sessionId": "s", "startTime": "2026-07-25 13:00:00.000",
            "stateDuration": 240, "type": "asleep"}]}
        """
        let dto = try JSONDecoder().decode(SnooAggregatedDayDTO.self, from: data(json))
        XCTAssertTrue(SnooSessionNormaliser.sessions(fromAggregated: dto).isEmpty)
    }

    func testAggregatedSegmentWithoutSessionIDGetsStableSynthesisedID() throws {
        let json = """
        {"levels": [
           {"startTime": "2026-07-25 13:00:00.000", "stateDuration": 3600, "type": "asleep"}]}
        """
        let dto = try JSONDecoder().decode(SnooAggregatedDayDTO.self, from: data(json))
        let a = SnooSessionNormaliser.sessions(fromAggregated: dto)
        let b = SnooSessionNormaliser.sessions(fromAggregated: dto)
        XCTAssertEqual(a[0].id, b[0].id)             // stable across syncs
        XCTAssertTrue(a[0].id.hasPrefix("snoo-"))
    }

    /// Live capture 2026-07-31 from `/ss/me/v10/babies/{id}/sessions/daily`
    /// (see docs/SNOO-API.md §C.2): segments of one bassinet session share a
    /// sessionId and must coalesce into a single span, not one session per
    /// asleep segment (same-id sessions would otherwise collapse to the
    /// first segment and lose the rest of the night).
    func testAggregatedCoalescesSegmentsOfOneSessionIntoOneSpan() throws {
        let json = """
        {"levels": [
           {"sessionId": "2035974117684732908", "type": "asleep",
            "startTime": "2026-07-30 23:53:34.396", "stateDuration": 14,
            "isActive": false, "startTimeFormatted": "2026-07-30T23:53:34-0500"},
           {"sessionId": "2035974117684732908", "type": "soothing",
            "startTime": "2026-07-30 23:53:48.620", "stateDuration": 1110,
            "isActive": false, "startTimeFormatted": "2026-07-30T23:53:48-0500"},
           {"sessionId": "2035974117684732908", "type": "asleep",
            "startTime": "2026-07-31 00:12:18.620", "stateDuration": 5400,
            "isActive": false, "startTimeFormatted": "2026-07-31T00:12:18-0500"}]}
        """
        let dto = try JSONDecoder().decode(SnooAggregatedDayDTO.self, from: data(json))
        let sessions = SnooSessionNormaliser.sessions(fromAggregated: dto)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, "2035974117684732908")
        let expectedStart = try XCTUnwrap(SnooDates.parse("2026-07-30 23:53:34.396"))
        let expectedEnd = try XCTUnwrap(SnooDates.parse("2026-07-31 00:12:18.620"))
            .addingTimeInterval(5400)
        XCTAssertEqual(sessions[0].startedAt, expectedStart)
        XCTAssertEqual(sessions[0].endedAt, expectedEnd)
    }

    func testAggregatedSpanFloorAppliesToWholeSessionNotSegments() throws {
        // Each asleep segment is under 5 minutes, but the session span isn't.
        let json = """
        {"levels": [
           {"sessionId": "s1", "type": "asleep",
            "startTime": "2026-07-30 22:00:00.000", "stateDuration": 19},
           {"sessionId": "s1", "type": "soothing",
            "startTime": "2026-07-30 22:00:19.000", "stateDuration": 236},
           {"sessionId": "s1", "type": "asleep",
            "startTime": "2026-07-30 22:04:15.000", "stateDuration": 60}]}
        """
        let dto = try JSONDecoder().decode(SnooAggregatedDayDTO.self, from: data(json))
        XCTAssertEqual(SnooSessionNormaliser.sessions(fromAggregated: dto).count, 1)
    }

    func testAggregatedDropsSessionWithNoSleepSegments() throws {
        // A run where the baby never slept (all soothing) is not a sleep session.
        let json = """
        {"levels": [
           {"sessionId": "s2", "type": "soothing",
            "startTime": "2026-07-30 22:00:00.000", "stateDuration": 1200}]}
        """
        let dto = try JSONDecoder().decode(SnooAggregatedDayDTO.self, from: data(json))
        XCTAssertTrue(SnooSessionNormaliser.sessions(fromAggregated: dto).isEmpty)
    }

    func testAggregatedActiveSegmentMakesWholeSessionInProgress() throws {
        let json = """
        {"levels": [
           {"sessionId": "s3", "type": "asleep",
            "startTime": "2026-07-31 20:00:00.000", "stateDuration": 3600},
           {"sessionId": "s3", "type": "soothing",
            "startTime": "2026-07-31 21:00:00.000", "stateDuration": 120, "isActive": true}]}
        """
        let dto = try JSONDecoder().decode(SnooAggregatedDayDTO.self, from: data(json))
        let sessions = SnooSessionNormaliser.sessions(fromAggregated: dto)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertTrue(sessions[0].isInProgress)
    }

    // MARK: Merge / dedupe

    func testMergePrefersLastSessionOverMatchingAggregatedSegment() {
        let start = Date(timeIntervalSince1970: 1_785_100_000)
        let aggregated = SnooSession(id: "123", startedAt: start,
                                     endedAt: start.addingTimeInterval(3600), levels: [])
        // Same session seen via /last: no sessionId there, started 2s apart.
        let last = SnooSession(id: SnooSession.synthesisedID(startedAt: start.addingTimeInterval(2)),
                               startedAt: start.addingTimeInterval(2), endedAt: nil, levels: [])
        let merged = SnooSessionNormaliser.merge(last: last, aggregated: [aggregated])
        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(merged[0].isInProgress)        // the fresher record won
    }

    func testMergeKeepsDistinctSessions() {
        let t0 = Date(timeIntervalSince1970: 1_785_100_000)
        let a = SnooSession(id: "a", startedAt: t0, endedAt: t0.addingTimeInterval(3600), levels: [])
        let lastStart = t0.addingTimeInterval(8000)
        let last = SnooSession(id: SnooSession.synthesisedID(startedAt: lastStart),
                               startedAt: lastStart, endedAt: nil, levels: [])
        let merged = SnooSessionNormaliser.merge(last: last, aggregated: [a])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].startedAt, lastStart)   // most recent first
    }

    func testMergeUnionsSessionClippedAcrossDayWindows() {
        // A midnight-spanning session comes back clipped in both day fetches
        // under the same sessionId — the merge should restore the full span.
        let midnight = Date(timeIntervalSince1970: 1_785_100_000)
        let yesterdayChunk = SnooSession(id: "night", startedAt: midnight.addingTimeInterval(-3600),
                                         endedAt: midnight, levels: [])
        let todayChunk = SnooSession(id: "night", startedAt: midnight,
                                     endedAt: midnight.addingTimeInterval(5400), levels: [])
        let merged = SnooSessionNormaliser.merge(last: nil,
                                                 aggregated: [todayChunk, yesterdayChunk])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].startedAt, midnight.addingTimeInterval(-3600))
        XCTAssertEqual(merged[0].endedAt, midnight.addingTimeInterval(5400))
    }

    func testMergeUnionStaysOpenWhenEitherHalfIsRunning() {
        let midnight = Date(timeIntervalSince1970: 1_785_100_000)
        let yesterdayChunk = SnooSession(id: "night", startedAt: midnight.addingTimeInterval(-3600),
                                         endedAt: midnight, levels: [])
        let todayChunk = SnooSession(id: "night", startedAt: midnight, endedAt: nil, levels: [])
        let merged = SnooSessionNormaliser.merge(last: nil,
                                                 aggregated: [todayChunk, yesterdayChunk])
        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(merged[0].isInProgress)
    }

    // MARK: Date parsing

    func testDateParserHandlesAllObservedFormats() {
        XCTAssertNotNil(SnooDates.parse("2026-07-25T19:50:06.296Z"))
        XCTAssertNotNil(SnooDates.parse("2026-07-25T19:50:06Z"))
        XCTAssertNotNil(SnooDates.parse("2026-07-25 07:09:10.215"))
        XCTAssertNotNil(SnooDates.parse("2026-07-25 07:09:10"))
        XCTAssertNotNil(SnooDates.parse("2026-07-25T07:09:10.215"))
        XCTAssertNil(SnooDates.parse(nil))
        XCTAssertNil(SnooDates.parse(""))
        XCTAssertNil(SnooDates.parse("not a date"))
    }

    func testAggregatedQueryStringFormat() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 7, day: 25))!
        XCTAssertEqual(SnooDates.queryString(from: midnight), "2026-07-25 00:00:00.000")
    }

    // MARK: Sync-state semantics (imported IDs survive sign-out — §5)

    func testSignOutResetKeepsImportedIDs() throws {
        let suiteName = "SnooDecodingTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = SnooSyncState(defaults: defaults)
        state.importedSessionIDs = ["kept"]
        state.dismissedSessionIDs = ["gone"]
        state.lastSyncAt = .now
        state.consecutiveDecodeFailures = 5
        state.registerRateLimit(retryAfter: 60)

        state.resetForSignOut()
        XCTAssertEqual(state.importedSessionIDs, ["kept"])
        XCTAssertTrue(state.dismissedSessionIDs.isEmpty)
        XCTAssertNil(state.lastSyncAt)
        XCTAssertNil(state.backoffUntil)
        XCTAssertEqual(state.consecutiveDecodeFailures, 0)
        XCTAssertFalse(state.isDegraded)
    }

    func testRateLimitBackoffDoublesToCeiling() throws {
        let suiteName = "SnooDecodingTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = SnooSyncState(defaults: defaults)
        let now = Date.now

        // No Retry-After: floor is 30 min, then doubling, capped at 4 h.
        state.registerRateLimit(retryAfter: nil, now: now)
        XCTAssertEqual(state.backoffUntil!.timeIntervalSince(now), 30 * 60, accuracy: 1)
        state.registerRateLimit(retryAfter: nil, now: now)
        XCTAssertEqual(state.backoffUntil!.timeIntervalSince(now), 60 * 60, accuracy: 1)
        for _ in 0..<5 { state.registerRateLimit(retryAfter: nil, now: now) }
        XCTAssertEqual(state.backoffUntil!.timeIntervalSince(now), 4 * 3600, accuracy: 1)

        // Retry-After below the floor is raised to the floor (§9).
        state.clearBackoff()
        state.registerRateLimit(retryAfter: 10, now: now)
        XCTAssertEqual(state.backoffUntil!.timeIntervalSince(now), 30 * 60, accuracy: 1)
    }

    func testDegradedAfterThreeConsecutiveDecodeFailures() throws {
        let suiteName = "SnooDecodingTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = SnooSyncState(defaults: defaults)

        state.consecutiveDecodeFailures = 2
        XCTAssertFalse(state.isDegraded)
        state.consecutiveDecodeFailures = 3
        XCTAssertTrue(state.isDegraded)
    }
}
