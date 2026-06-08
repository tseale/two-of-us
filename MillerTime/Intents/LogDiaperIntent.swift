import AppIntents

/// AppIntents-facing mirror of `DiaperType` (the model enum stays free of the
/// AppIntents dependency). Used as the parameter for `LogDiaperIntent`.
enum DiaperTypeAppEnum: String, AppEnum {
    case wet, dirty, both

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Diaper Type" }

    static var caseDisplayRepresentations: [DiaperTypeAppEnum: DisplayRepresentation] {
        [.wet: "Wet", .dirty: "Dirty", .both: "Both"]
    }

    var diaperType: DiaperType {
        switch self {
        case .wet: return .wet
        case .dirty: return .dirty
        case .both: return .both
        }
    }
}

/// Logs a diaper change for Miller without opening the app.
struct LogDiaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a Diaper"
    static var description = IntentDescription("Logs a diaper change for Miller.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Type", default: .wet)
    var type: DiaperTypeAppEnum

    init() {}
    init(type: DiaperTypeAppEnum = .wet) { self.type = type }

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickLogger.make()?.logDiaper(type.diaperType)
        return .result()
    }
}
