import AppIntents

// Read-only "ask Miller Time" intents. These never open the app and never write;
// they read the App Group-shared store via QuickLogger and speak the answer.
// Great for the one-handed 3am question: "Hey Siri, when did Miller last eat?"

/// "When did Miller last eat?"
struct LastFeedIntent: AppIntent {
    static var title: LocalizedStringResource = "When Did Miller Last Eat?"
    static var description = IntentDescription("Tells you how long ago Miller's last bottle was.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let logger = QuickLogger.make() else {
            return .result(dialog: "Couldn't reach Miller Time.")
        }
        let name = logger.babyName ?? "Miller"
        guard let feed = logger.lastFeed else {
            return .result(dialog: "No feeds logged for \(name) yet.")
        }
        let ago = TimeFormatting.since(feed.timestamp)
        let oz = OzFormat.string(feed.amountOz)
        return .result(dialog: "\(name) last ate \(oz) oz \(ago) ago, at \(TimeFormatting.clock(feed.timestamp)).")
    }
}

/// "When was Miller's last diaper?"
struct LastDiaperIntent: AppIntent {
    static var title: LocalizedStringResource = "When Was Miller's Last Diaper?"
    static var description = IntentDescription("Tells you how long ago Miller's last diaper change was.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let logger = QuickLogger.make() else {
            return .result(dialog: "Couldn't reach Miller Time.")
        }
        let name = logger.babyName ?? "Miller"
        guard let diaper = logger.lastDiaper else {
            return .result(dialog: "No diapers logged for \(name) yet.")
        }
        let ago = TimeFormatting.since(diaper.timestamp)
        return .result(dialog: "\(name)'s last diaper was a \(diaper.type.label.lowercased()) one, \(ago) ago.")
    }
}

/// "Is Miller asleep?" / "How long has Miller been sleeping?"
struct SleepStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Is Miller Asleep?"
    static var description = IntentDescription("Tells you whether Miller is asleep and for how long.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let logger = QuickLogger.make() else {
            return .result(dialog: "Couldn't reach Miller Time.")
        }
        let name = logger.babyName ?? "Miller"
        if let started = logger.activeSleep?.startedAt {
            let dur = TimeFormatting.duration(from: started, to: .now)
            return .result(dialog: "\(name) has been asleep for \(dur), since \(TimeFormatting.clock(started)).")
        }
        if let last = logger.lastEndedSleep, let end = last.endedAt {
            return .result(dialog: "\(name) is awake. The last sleep ended \(TimeFormatting.since(end)) ago.")
        }
        return .result(dialog: "\(name) is awake.")
    }
}

/// "How is Miller doing today?"
struct TodaySummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "How Is Miller Doing Today?"
    static var description = IntentDescription("Reads back today's feed, ounce, and diaper totals.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let logger = QuickLogger.make() else {
            return .result(dialog: "Couldn't reach Miller Time.")
        }
        let name = logger.babyName ?? "Miller"
        let t = logger.todayCounts
        let feedWord = t.feeds == 1 ? "feed" : "feeds"
        let diaperWord = t.diapers == 1 ? "diaper" : "diapers"
        return .result(dialog: "Today \(name) had \(t.feeds) \(feedWord) totaling \(OzFormat.string(t.oz)) oz, and \(t.diapers) \(diaperWord).")
    }
}

/// "Undo that in Miller Time" — soft-deletes the most recent log.
struct UndoLastLogIntent: AppIntent {
    static var title: LocalizedStringResource = "Undo Last Log"
    static var description = IntentDescription("Removes the most recently logged event for Miller.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let logger = QuickLogger.make() else {
            return .result(dialog: "Couldn't reach Miller Time.")
        }
        guard let removed = logger.undoLastLog() else {
            return .result(dialog: "There's nothing to undo.")
        }
        return .result(dialog: "Removed the \(removed).")
    }
}
