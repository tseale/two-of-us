import Foundation
import SwiftData

/// Builds a CSV backup of the live log (feeds, sleeps, diapers) so parents can
/// keep a record before clearing or deleting data. Pure read; no model changes.
/// Live (non-soft-deleted) events only.
enum LogExporter {
    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// One row per live event: kind, ISO-8601 timestamp, a human detail, who
    /// logged it, and notes. Rows are newest-first within each kind.
    static func csv(in context: ModelContext) -> String {
        var rows = ["kind,timestamp,detail,loggedBy,notes"]

        let feeds = (try? context.fetch(FetchDescriptor<FeedEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        ))) ?? []
        for f in feeds {
            rows.append(row("feed", f.timestamp, "\(formatOz(f.amountOz)) oz", f.loggedByName, f.notes))
        }

        let sleeps = (try? context.fetch(FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        ))) ?? []
        for s in sleeps {
            let detail = s.endedAt.map { "ended \(dateFormatter.string(from: $0))" } ?? "in progress"
            rows.append(row("sleep", s.startedAt, detail, s.loggedByName, s.notes))
        }

        let diapers = (try? context.fetch(FetchDescriptor<DiaperEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        ))) ?? []
        for d in diapers {
            rows.append(row("diaper", d.timestamp, d.type.label, d.loggedByName, d.notes))
        }

        return rows.joined(separator: "\n")
    }

    /// Writes the CSV to a temp file and returns its URL for `ShareLink`.
    static func writeTempFile(in context: ModelContext) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MillerTime-Log.csv")
        guard let data = csv(in: context).data(using: .utf8) else { return nil }
        do { try data.write(to: url); return url } catch { return nil }
    }

    // MARK: Helpers

    private static func row(_ kind: String, _ date: Date, _ detail: String,
                            _ loggedBy: String, _ notes: String?) -> String {
        [kind, dateFormatter.string(from: date), detail, loggedBy, notes ?? ""]
            .map(escape).joined(separator: ",")
    }

    private static func formatOz(_ oz: Double) -> String {
        oz.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(oz)) : String(format: "%.1f", oz)
    }

    /// RFC-4180 CSV field escaping.
    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
