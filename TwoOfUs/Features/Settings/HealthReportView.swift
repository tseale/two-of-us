import SwiftUI

/// A clean, printable care summary for a pediatrician visit. Deliberately
/// *clinical*, not the app's playful style: white page, legible system type, a
/// metrics row and a per-day table. Rendered to a PDF via `HealthReportPDF`.
struct HealthReportView: View {
    let babyName: String
    let dateOfBirth: Date?
    let days: Int
    let engine: StatsEngine

    private var summaries: [DaySummary] { engine.dailySummaries(days: days) }
    private var diaperDays: [DiaperDay] { engine.diaperDays(days: days) }

    /// One table row, pairing a day's feed/sleep totals with its diaper split.
    /// Wet/Dirty include "both" diapers (a "both" is both wet and dirty).
    private struct Row: Identifiable {
        var id: Date { day }
        let day: Date
        let feeds: Int
        let oz: Double
        let sleepHours: Double
        let wet: Int
        let dirty: Int
    }

    private var rows: [Row] {
        zip(summaries, diaperDays).map { s, d in
            Row(day: s.day, feeds: s.feedCount, oz: s.feedOz,
                sleepHours: s.sleepSeconds / 3600, wet: d.wet + d.both, dirty: d.dirty + d.both)
        }
    }

    private var dayCount: Double { Double(max(rows.count, 1)) }
    private var totalFeeds: Int { rows.reduce(0) { $0 + $1.feeds } }
    private var totalOz: Double { rows.reduce(0) { $0 + $1.oz } }
    private var totalSleep: Double { rows.reduce(0) { $0 + $1.sleepHours } }
    private var totalWet: Int { rows.reduce(0) { $0 + $1.wet } }
    private var totalDirty: Int { rows.reduce(0) { $0 + $1.dirty } }
    private var longestStretch: Double { (summaries.map(\.longestStretch).max() ?? 0) / 3600 }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            metrics
            table
            footer
        }
        .padding(40)
        .frame(width: 612, alignment: .topLeading)   // US Letter width @ 72dpi
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Care Summary")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color(hex: "0B7E70"))   // a calm clinical teal
            Text(babyName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.black)
            if let dob = dateOfBirth {
                // Future date of birth = due date; the age suffix would repeat
                // "due", so the pre-arrival form is just "Due <date>".
                Text(dob <= .now
                     ? "Born \(Self.long(dob)) · \(TimeFormatting.age(from: dob))"
                     : "Due \(Self.long(dob))")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Text("\(days)-day summary"
                 + dateRangeSuffix
                 + " · generated \(Self.long(.now))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var dateRangeSuffix: String {
        guard let first = rows.first, let last = rows.last else { return "" }
        return " · \(Self.short(first.day)) – \(Self.short(last.day))"
    }

    // MARK: Metrics

    private var metrics: some View {
        HStack(spacing: 12) {
            metric("Feeds / day", String(format: "%.1f", Double(totalFeeds) / dayCount))
            metric("Oz / day", String(format: "%.0f", totalOz / dayCount))
            metric("Sleep / day", String(format: "%.1fh", totalSleep / dayCount))
            metric("Longest sleep", String(format: "%.1fh", longestStretch))
            metric("Wet / day", String(format: "%.1f", Double(totalWet) / dayCount))
            metric("Dirty / day", String(format: "%.1f", Double(totalDirty) / dayCount))
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundStyle(.black)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(hex: "F2F6F5"), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Daily table

    private var table: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily detail")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.black)
            Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 7) {
                GridRow {
                    cell("Date", bold: true, leading: true)
                    cell("Feeds", bold: true)
                    cell("Oz", bold: true)
                    cell("Sleep", bold: true)
                    cell("Wet", bold: true)
                    cell("Dirty", bold: true)
                }
                Divider()
                ForEach(rows) { r in
                    GridRow {
                        cell(Self.short(r.day), leading: true)
                        cell("\(r.feeds)")
                        cell(String(format: "%.0f", r.oz))
                        cell(String(format: "%.1f", r.sleepHours))
                        cell("\(r.wet)")
                        cell("\(r.dirty)")
                    }
                }
                Divider()
                GridRow {
                    cell("Total", bold: true, leading: true)
                    cell("\(totalFeeds)", bold: true)
                    cell(String(format: "%.0f", totalOz), bold: true)
                    cell(String(format: "%.0f", totalSleep), bold: true)
                    cell("\(totalWet)", bold: true)
                    cell("\(totalDirty)", bold: true)
                }
            }
        }
    }

    private func cell(_ text: String, bold: Bool = false, leading: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 12, weight: bold ? .semibold : .regular).monospacedDigit())
            .foregroundStyle(bold ? .black : Color(white: 0.2))
            .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
            .gridColumnAlignment(leading ? .leading : .trailing)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Wet and Dirty counts include “both” diapers. Times are device-local.")
            Text("Generated by Two of Us — a parent-kept log, not a medical record.")
        }
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
    }

    // MARK: Formatting

    // `.formatted` styles: locale-aware (a fixed "EEE MMM d" pattern isn't) and
    // backed by Foundation's formatter cache — no per-call allocation.
    private static func short(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
    private static func long(_ d: Date) -> String {
        d.formatted(date: .abbreviated, time: .omitted)
    }
}

/// Renders a `HealthReportView` to a single-page PDF file for sharing/printing.
enum HealthReportPDF {
    @MainActor
    static func render(_ report: HealthReportView, babyName: String) -> URL? {
        let renderer = ImageRenderer(content: report)
        let safeName = babyName.isEmpty ? "Baby" : babyName
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName)-care-summary.pdf")

        var ok = false
        renderer.render { size, renderInContext in
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(url: url as CFURL),
                  let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }
            pdf.beginPDFPage(nil)
            renderInContext(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            ok = true
        }
        return ok ? url : nil
    }
}
