import ActivityKit
import AVFoundation
import UserNotifications

/// The tone an AlarmKit alarm rings with — shared by the interval feed alarm
/// and the night-slot alarm, chosen per device in Settings → Reminders.
///
/// AlarmKit offers exactly two options: the system alarm sound, or a file
/// bundled with the app (`AlertSound.named`); there's no access to Apple's
/// ringtone library. The three custom tones are synthesized in-house (music
/// box, kalimba, and soft bells — see docs/ALARM_TONES.md) to be gentler than
/// the system default while still looping loud enough to wake a parent.
enum AlarmTone: String, CaseIterable, Identifiable {
    case nightlight, sunrise, bells, system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nightlight: "Nightlight"
        case .sunrise: "Sunrise"
        case .bells: "Bells"
        case .system: "System"
        }
    }

    /// Bundle resource the tone plays from; nil means the system alarm sound.
    var fileName: String? {
        switch self {
        case .nightlight: "alarm-nightlight.caf"
        case .sunrise: "alarm-sunrise.caf"
        case .bells: "alarm-bells.caf"
        case .system: nil
        }
    }

    /// What AlarmKit rings with.
    var alertSound: AlertConfiguration.AlertSound {
        fileName.map { .named($0) } ?? .default
    }

    /// The same tone for the local-notification fallback path, so a failed
    /// AlarmKit schedule still sounds like the alarm the parent picked.
    var notificationSound: UNNotificationSound {
        fileName.map { UNNotificationSound(named: UNNotificationSoundName($0)) } ?? .default
    }
}

/// Plays a tone once, out loud, when the user picks it in Settings — the one
/// deliberate exception to "no audio feedback": you can't choose an alarm
/// sound you've never heard, and `.playback` sidesteps the Silent switch the
/// same way the real alarm will.
@MainActor
enum AlarmTonePreview {
    private static var player: AVAudioPlayer?

    static func play(_ tone: AlarmTone) {
        guard let fileName = tone.fileName,
              let url = Bundle.main.url(forResource: fileName, withExtension: nil) else {
            player?.stop()
            return  // the system tone isn't previewable — no API exposes it
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}
