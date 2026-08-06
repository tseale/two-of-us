import SwiftUI
import SwiftData
import WatchKit

/// The whole watch app: three glance-and-tap rows.
/// Feed → one tap logs the default amount. Diaper → wet/dirty/both dialog.
/// Sleep → toggles the timer. Status text updates every 30s via TimelineView.
struct WatchRootView: View {
    @Environment(\.modelContext) private var context

    @Query(WatchRootView.lastFeedDescriptor) private var lastFeeds: [FeedEvent]
    @Query(WatchRootView.lastDiaperDescriptor) private var lastDiapers: [DiaperEvent]
    @Query(WatchRootView.openSleepDescriptor) private var openSleeps: [SleepEvent]
    @Query(WatchRootView.lastEndedSleepDescriptor) private var endedSleeps: [SleepEvent]
    @Query private var babies: [Baby]

    @State private var showDiaperPicker = false
    @State private var confirmation: String?
    @State private var confirmationTask: Task<Void, Never>?

    private var logger: QuickLogger { QuickLogger(context: context) }

    var body: some View {
        Group {
            if babies.isEmpty {
                waitingForSync
            } else {
                rows
            }
        }
        .overlay(alignment: .bottom) {
            if let confirmation {
                Text(confirmation)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.green.opacity(0.85), in: Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: confirmation)
    }

    private var rows: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            List {
                Button { logFeed() } label: {
                    row(icon: "waterbottle.fill", tint: .orange, title: "Feed",
                        subtitle: lastFeeds.first.map {
                            "\(OzFormat.string($0.amountOz)) oz · \(TimeFormatting.since($0.timestamp, now: timeline.date)) ago"
                        } ?? "No feeds yet")
                }
                Button { showDiaperPicker = true } label: {
                    row(icon: "drop.fill", tint: .teal, title: "Diaper",
                        subtitle: lastDiapers.first.map {
                            "\($0.type.label) · \(TimeFormatting.since($0.timestamp, now: timeline.date)) ago"
                        } ?? "No changes yet")
                }
                Button { toggleSleep() } label: {
                    if let open = openSleeps.first {
                        row(icon: "moon.zzz.fill", tint: .indigo, title: "Sleeping",
                            subtitle: "\(TimeFormatting.duration(from: open.startedAt, to: timeline.date)) — tap to wake")
                    } else {
                        row(icon: "moon.fill", tint: .indigo, title: "Sleep",
                            subtitle: endedSleeps.first.flatMap { sleep in
                                sleep.endedAt.map {
                                    "Woke \(TimeFormatting.since($0, now: timeline.date)) ago"
                                }
                            } ?? "Tap to start")
                    }
                }
            }
        }
        .confirmationDialog("Diaper", isPresented: $showDiaperPicker) {
            ForEach(DiaperType.allCases) { type in
                Button(type.label) { logDiaper(type) }
            }
        }
    }

    private var waitingForSync: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Waiting for iPhone data…")
                .font(.footnote)
                .multilineTextAlignment(.center)
            Text("Set up Two of Us on your iPhone, then give the watch a moment to sync.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    private func row(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Actions

    private func logFeed() {
        let amount = logger.defaultFeedOz
        if logger.logFeed(amountOz: amount) != nil {
            didLog("Logged \(OzFormat.string(amount)) oz")
        } else {
            didFail()
        }
    }

    private func logDiaper(_ type: DiaperType) {
        if logger.logDiaper(type) != nil {
            didLog("Logged \(type.label.lowercased()) diaper")
        } else {
            didFail()
        }
    }

    private func toggleSleep() {
        switch logger.toggleSleep() {
        case true?: didLog("Sleep started")
        case false?: didLog("Sleep ended")
        case nil: didFail()
        }
    }

    private func didLog(_ message: String) {
        WKInterfaceDevice.current().play(.success)
        WatchSyncManager.shared?.drainLoggerQueue()
        showConfirmation(message)
    }

    private func didFail() {
        WKInterfaceDevice.current().play(.failure)
        showConfirmation("Couldn't log — try from the phone")
    }

    private func showConfirmation(_ message: String) {
        confirmationTask?.cancel()
        confirmation = message
        confirmationTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            confirmation = nil
        }
    }

    // MARK: Queries

    private static var lastFeedDescriptor: FetchDescriptor<FeedEvent> {
        var d = FetchDescriptor<FeedEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        d.fetchLimit = 1
        return d
    }

    private static var lastDiaperDescriptor: FetchDescriptor<DiaperEvent> {
        var d = FetchDescriptor<DiaperEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        d.fetchLimit = 1
        return d
    }

    private static var openSleepDescriptor: FetchDescriptor<SleepEvent> {
        var d = FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.endedAt == nil && $0.deletedAt == nil }
        )
        d.fetchLimit = 1
        return d
    }

    private static var lastEndedSleepDescriptor: FetchDescriptor<SleepEvent> {
        var d = FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.endedAt != nil },
            sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
        )
        d.fetchLimit = 1
        return d
    }
}
