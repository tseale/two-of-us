import Foundation

// Typed vocabularies for the daycare-era event models (ActivityEvent,
// CheckEvent, HealthCheckEvent, MoodEvent, PottyEvent, MilestoneEvent…).
// Same conventions as DiaperType: String raw values travel on the synced
// records, so cases are additive-only and never renamed.

/// What kind of activity the daycare ran.
enum ActivityType: String, Codable, CaseIterable, Identifiable {
    case tummyTime
    case outdoorPlay
    case crafts
    case reading
    case circleTime
    case sensoryPlay
    case music
    case freePlay

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tummyTime: return "Tummy Time"
        case .outdoorPlay: return "Outdoor Play"
        case .crafts: return "Crafts"
        case .reading: return "Reading"
        case .circleTime: return "Circle Time"
        case .sensoryPlay: return "Sensory Play"
        case .music: return "Music"
        case .freePlay: return "Free Play"
        }
    }

    var emoji: String {
        switch self {
        case .tummyTime: return "🤸"
        case .outdoorPlay: return "🌳"
        case .crafts: return "🎨"
        case .reading: return "📚"
        case .circleTime: return "🙌"
        case .sensoryPlay: return "✨"
        case .music: return "🎶"
        case .freePlay: return "🧸"
        }
    }
}

/// Photo vs. video, for MediaEvent.
enum MediaKind: String, Codable, CaseIterable, Identifiable {
    case photo
    case video

    var id: String { rawValue }

    var label: String {
        switch self {
        case .photo: return "Photo"
        case .video: return "Video"
        }
    }

    var emoji: String {
        switch self {
        case .photo: return "📷"
        case .video: return "🎬"
        }
    }
}

/// Arrival vs. departure, for CheckEvent.
enum CheckType: String, Codable, CaseIterable, Identifiable {
    case checkIn
    case checkOut

    var id: String { rawValue }

    var label: String {
        switch self {
        case .checkIn: return "Checked in"
        case .checkOut: return "Checked out"
        }
    }

    var emoji: String {
        switch self {
        case .checkIn: return "🏫"
        case .checkOut: return "🏠"
        }
    }
}

/// What a HealthCheckEvent measured.
enum HealthCheckType: String, Codable, CaseIterable, Identifiable {
    case temperature
    case weight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .temperature: return "Temp"
        case .weight: return "Weight"
        }
    }

    var emoji: String {
        switch self {
        case .temperature: return "🌡️"
        case .weight: return "⚖️"
        }
    }

    /// "98.6°F" / "12.4 lb" — the value is stored unit-less; the type owns
    /// the display unit until the real wire teaches us otherwise.
    func format(_ value: Double) -> String {
        switch self {
        case .temperature:
            return value.formatted(.number.precision(.fractionLength(0...1))) + "°F"
        case .weight:
            return value.formatted(.number.precision(.fractionLength(0...1))) + " lb"
        }
    }
}

/// How the day is going, for MoodEvent.
enum MoodLevel: String, Codable, CaseIterable, Identifiable {
    case happy
    case content
    case fussy
    case upset
    case sleepy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .happy: return "Happy"
        case .content: return "Content"
        case .fussy: return "Fussy"
        case .upset: return "Upset"
        case .sleepy: return "Sleepy"
        }
    }

    var emoji: String {
        switch self {
        case .happy: return "😊"
        case .content: return "🙂"
        case .fussy: return "😣"
        case .upset: return "😢"
        case .sleepy: return "😴"
        }
    }
}

/// Toilet-training outcome, for PottyEvent — distinct from DiaperType, which
/// describes what was in a diaper. Not relevant at 2 months; modeled now so
/// the schema is already additive-complete when it becomes relevant.
enum PottyOutcome: String, Codable, CaseIterable, Identifiable {
    case attempt
    case success
    case accident

    var id: String { rawValue }

    var label: String {
        switch self {
        case .attempt: return "Attempt"
        case .success: return "Success"
        case .accident: return "Accident"
        }
    }
}

/// Development domain of a MilestoneEvent.
enum MilestoneCategory: String, Codable, CaseIterable, Identifiable {
    case physical
    case cognitive
    case social
    case language

    var id: String { rawValue }

    var label: String {
        switch self {
        case .physical: return "Physical"
        case .cognitive: return "Cognitive"
        case .social: return "Social"
        case .language: return "Language"
        }
    }
}
