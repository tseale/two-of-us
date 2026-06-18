import XCTest
import SwiftData
@testable import TwoOfUs

/// The CSV backup is the only way data leaves the app before "Delete everything"
/// — these pin down what it includes (live events only), how fields are escaped
/// (RFC 4180), and the human-readable details.
@MainActor
final class LogExporterTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() {
        super.setUp()
        container = AppModelContainer.make(inMemory: true)
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private func lines() -> [String] {
        LogExporter.csv(in: context).components(separatedBy: "\n")
    }

    func testHeaderRowComesFirst() {
        XCTAssertEqual(lines().first, "kind,timestamp,detail,loggedBy,loggedByColor,notes")
    }

    func testRowCarriesLoggerColor() throws {
        context.insert(FeedEvent(baby: nil, amountOz: 3, timestamp: .now,
                                 loggedByID: UUID(), loggedByName: "Taylor", loggedByColorHex: "#AABBCC"))
        try? context.save()
        let row = try XCTUnwrap(lines().dropFirst().first)
        XCTAssertTrue(row.contains("#AABBCC"), "the logger's color travels in its own column — got: \(row)")
    }

    func testSoftDeletedEventsAreExcluded() {
        context.insert(FeedEvent(baby: nil, amountOz: 3, timestamp: .now,
                                 loggedByID: UUID(), loggedByName: "Taylor",
                                 loggedByColorHex: "#AABBCC", deletedAt: .now))
        try? context.save()
        XCTAssertEqual(lines().count, 1, "only the header — deleted events never export")
    }

    func testOzFormattingDropsTrailingZero() throws {
        context.insert(FeedEvent(baby: nil, amountOz: 3.0, timestamp: .now,
                                 loggedByID: UUID(), loggedByName: "Taylor", loggedByColorHex: "#AABBCC"))
        context.insert(FeedEvent(baby: nil, amountOz: 2.5, timestamp: .now.addingTimeInterval(-60),
                                 loggedByID: UUID(), loggedByName: "Taylor", loggedByColorHex: "#AABBCC"))
        try? context.save()

        let csv = LogExporter.csv(in: context)
        XCTAssertTrue(csv.contains("3 oz"), "whole ounces export without a decimal")
        XCTAssertTrue(csv.contains("2.5 oz"))
    }

    func testActiveSleepExportsAsInProgress() {
        context.insert(SleepEvent(baby: nil, startedAt: .now, loggedByID: UUID(),
                                  loggedByName: "Taylor", loggedByColorHex: "#AABBCC"))
        try? context.save()
        XCTAssertTrue(LogExporter.csv(in: context).contains("in progress"))
    }

    func testFieldsWithCommasAndQuotesAreEscaped() throws {
        let feed = FeedEvent(baby: nil, amountOz: 3, timestamp: .now,
                             loggedByID: UUID(), loggedByName: "Taylor", loggedByColorHex: "#AABBCC")
        feed.notes = #"fussy, said "no" twice"#
        context.insert(feed)
        try? context.save()

        let row = try XCTUnwrap(lines().dropFirst().first)
        XCTAssertTrue(row.hasSuffix(#""fussy, said ""no"" twice""#),
                      "RFC 4180: quote the field, double the quotes — got: \(row)")
    }

    func testWriteTempFileProducesAReadableCSV() throws {
        context.insert(DiaperEvent(baby: nil, type: .both, timestamp: .now,
                                   loggedByID: UUID(), loggedByName: "Katie", loggedByColorHex: "#112233"))
        try? context.save()

        let url = try XCTUnwrap(LogExporter.writeTempFile(in: context))
        defer { try? FileManager.default.removeItem(at: url) }
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.hasPrefix("kind,timestamp,"))
        XCTAssertTrue(contents.contains("Both"))
    }
}
