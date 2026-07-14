import SwiftUI

/// Presents the printable "Care Summary" with a range toggle and a Share
/// button — the checkup companion to `WrappedShareView`. The US-Letter page
/// (`HealthReportView`) is rendered to an image so it can scale down to a
/// phone-width preview; the shareable PDF re-renders whenever the range flips.
struct CareSummarySheet: View {
    let babyName: String
    let dateOfBirth: Date?
    let engine: StatsEngine

    @Environment(\.dismiss) private var dismiss
    @State private var days = 14
    @State private var reportURL: URL?
    @State private var preview: UIImage?
    @State private var renderFailed = false
    @State private var renderRetry = 0

    private var report: HealthReportView {
        HealthReportView(babyName: babyName, dateOfBirth: dateOfBirth,
                         days: days, engine: engine)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Picker("Range", selection: $days) {
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                    }
                    .pickerStyle(.segmented)

                    if let preview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                            // Decorative — the footer line says what the page holds.
                            .accessibilityHidden(true)
                    } else if renderFailed {
                        Button { renderRetry += 1 } label: {
                            Label("Couldn't build the report — tap to try again",
                                  systemImage: "arrow.clockwise")
                                .foregroundStyle(AppColor.urgencyAmber)
                        }
                        .frame(maxWidth: .infinity, minHeight: 240)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 240)
                    }

                    Text("A printable \(days)-day summary: feeds, ounces, sleep, and wet/dirty diapers per day, with averages.")
                        .font(.footnote)
                        .foregroundStyle(AppColor.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .background(AppColor.bg)
            .navigationTitle("Care summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if let reportURL {
                        ShareLink(item: reportURL) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    } else if !renderFailed {
                        ProgressView()
                    }
                }
            }
            // Re-render preview + PDF when the range changes or on "try again".
            .task(id: "\(days)-\(renderRetry)") {
                reportURL = nil
                preview = nil
                renderFailed = false
                let renderer = ImageRenderer(content: report)
                renderer.scale = 2
                let image = renderer.uiImage
                let url = HealthReportPDF.render(report, babyName: babyName)
                preview = image
                reportURL = url
                renderFailed = (url == nil || image == nil)
            }
        }
    }
}

#Preview {
    CareSummarySheet(babyName: "Miller", dateOfBirth: .now.addingTimeInterval(-86_400 * 40),
                     engine: StatsEngine(feeds: [], sleeps: [], diapers: []))
}
