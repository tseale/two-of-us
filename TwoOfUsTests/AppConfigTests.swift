import XCTest
@testable import TwoOfUs

/// Pins the Info.plist declarations the CloudKit layer silently depends on.
/// These are easy to lose in a project.yml edit, and nothing else fails loudly:
/// the app builds and runs fine — sharing or background sync just stops working.
/// The tests run hosted inside the real app bundle, so they check what ships.
final class AppConfigTests: XCTestCase {
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    func testAppDeclaresCloudKitSharingSupport() {
        // Without CKSharingSupported, iOS never routes a tapped invite link into
        // the app — the share-accept delegates simply don't fire.
        XCTAssertEqual(info["CKSharingSupported"] as? Bool, true)
    }

    func testRemoteNotificationBackgroundModeIsOn() {
        // CKSyncEngine's silent pushes (what keeps the other parent's widget
        // fresh without opening the app) need the remote-notification mode.
        let modes = info["UIBackgroundModes"] as? [String] ?? []
        XCTAssertTrue(modes.contains("remote-notification"))
    }

    func testAppRegistersTwoOfUsURLScheme() {
        // Widget / lock-screen taps deep-link via twoofus://log/<kind>. Without
        // the scheme registered here, iOS won't route the tap into the app and
        // the widgets become inert — nothing else fails loudly.
        let types = info["CFBundleURLTypes"] as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertTrue(schemes.contains("twoofus"))
    }
}
