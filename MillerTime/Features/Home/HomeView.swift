import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context

    @Query private var babies: [Baby]
    @Query private var settingsList: [SharedSettings]
    @Query(filter: #Predicate<FeedEvent> { $0.deletedAt == nil }, sort: \FeedEvent.timestamp, order: .reverse)
    private var feeds: [FeedEvent]
    @Query(filter: #Predicate<SleepEvent> { $0.deletedAt == nil }, sort: \SleepEvent.startedAt, order: .reverse)
    private var sleeps: [SleepEvent]
    @Query(filter: #Predicate<DiaperEvent> { $0.deletedAt == nil }, sort: \DiaperEvent.timestamp, order: .reverse)
    private var diapers: [DiaperEvent]

    @State private var activeSheet: ActiveSheet?
    @State private var editing: TimelineEntry?
    @State private var toast: ToastData?
    @State private var showSettings = false

    private enum ActiveSheet: String, Identifiable { case feed, diaper; var id: String { rawValue } }

    private var baby: Baby? { babies.first }
    private var store: EventStore { EventStore(context: context) }
    private var activeSleep: SleepEvent? { sleeps.first { $0.isActive } }
    private var targetFeed: TimeInterval {
        TimeInterval((settingsList.first?.targetFeedIntervalMinutes ?? 180) * 60)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        VStack(spacing: 18) {
                            statusRow(now: ctx.date)
                            if let sleep = activeSleep {
                                SleepActiveCard(sleep: sleep, now: ctx.date) { store.stopSleep(sleep) }
                            }
                            logButtons
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                timelineSection
            }
            .listStyle(.plain)
            .background(AppColor.bg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .tint(AppColor.text3)
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .feed: FeedSheet(onLogged: showToast)
                case .diaper: DiaperSheet(onLogged: showToast)
                }
            }
            .sheet(item: $editing) { entry in
                EditEventSheet(entry: entry)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .loggedToast($toast)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(baby?.name ?? "Miller")
                    .font(.largeTitle.weight(.bold))
                if let dob = baby?.dateOfBirth {
                    Text(TimeFormatting.age(from: dob))
                        .font(.subheadline)
                        .foregroundStyle(AppColor.text2)
                }
            }
            Spacer()
        }
    }

    // MARK: Status row

    private func statusRow(now: Date) -> some View {
        HStack(spacing: 8) {
            StatusPill(
                emoji: "🍼",
                value: feeds.first.map { TimeFormatting.since($0.timestamp, now: now) } ?? "—",
                label: "SINCE FEED",
                urgency: .from(since: feeds.first?.timestamp, now: now, target: targetFeed)
            )
            if activeSleep == nil {
                StatusPill(
                    emoji: "💤",
                    value: lastSleepEnd.map { TimeFormatting.since($0, now: now) } ?? "—",
                    label: "SINCE SLEEP",
                    urgency: .from(since: lastSleepEnd, now: now, target: UrgencyDefaults.sleep)
                )
            }
            StatusPill(
                emoji: "💩",
                value: diapers.first.map { TimeFormatting.since($0.timestamp, now: now) } ?? "—",
                label: "SINCE DIAPER",
                urgency: .from(since: diapers.first?.timestamp, now: now, target: UrgencyDefaults.diaper)
            )
        }
    }

    private var lastSleepEnd: Date? {
        sleeps.first(where: { $0.endedAt != nil })?.endedAt
    }

    // MARK: Log buttons

    private var logButtons: some View {
        LogButtons(
            sleepActive: activeSleep != nil,
            onFeed: { activeSheet = .feed },
            onSleep: startSleep,
            onDiaper: { activeSheet = .diaper }
        )
    }

    private func startSleep() {
        guard let event = store.startSleep() else { return }
        showToast("Started sleep") { store.softDelete(event) }
    }

    // MARK: Timeline

    @ViewBuilder
    private var timelineSection: some View {
        Section {
            if timelineEntries.isEmpty {
                Text("No events yet — tap 🍼 to log Miller's first feed.")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(timelineEntries) { entry in
                    TimelineRow(entry: entry)
                        .contentShape(Rectangle())
                        .onTapGesture { editing = entry }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(entry) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        } header: {
            Text("Recent").foregroundStyle(AppColor.text3)
        }
    }

    private var timelineEntries: [TimelineEntry] {
        let since = Calendar.current.date(byAdding: .hour, value: -24, to: .now) ?? .now
        var entries: [TimelineEntry] = []
        entries += feeds.filter { $0.timestamp >= since }.map(TimelineEntry.feed)
        entries += sleeps.filter { !$0.isActive && $0.startedAt >= since }.map(TimelineEntry.sleep)
        entries += diapers.filter { $0.timestamp >= since }.map(TimelineEntry.diaper)
        return entries.sorted { $0.sortDate > $1.sortDate }
    }

    // MARK: Actions

    private func delete(_ entry: TimelineEntry) {
        switch entry {
        case .feed(let e): store.softDelete(e)
        case .sleep(let e): store.softDelete(e)
        case .diaper(let e): store.softDelete(e)
        }
        Haptics.warning()
    }

    private func showToast(_ message: String, undo: @escaping () -> Void) {
        toast = ToastData(message: message, undo: undo)
    }
}

#Preview {
    HomeView()
        .modelContainer(AppModelContainer.preview)
}
