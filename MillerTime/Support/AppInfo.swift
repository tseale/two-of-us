import Foundation

/// Bundle version/build, surfaced in the Settings About footer.
enum AppInfo {
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?" }
    static var versionString: String { "Version \(version) (\(build))" }
}
