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

    func testAppRegistersWidgetDeepLinkScheme() {
        // The Feed/Diaper home widgets open the app on twoofus://log/… — without
        // the registered URL scheme iOS never routes the tap and the tile dead-ends.
        let types = info["CFBundleURLTypes"] as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertTrue(schemes.contains("twoofus"))
    }
}
