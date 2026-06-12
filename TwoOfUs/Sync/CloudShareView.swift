import SwiftUI
import UIKit
import CloudKit

/// Presents the system share sheet (`UICloudSharingController`) for an already
/// prepared zone-wide `CKShare`, so the owner can invite the co-parent via
/// Messages/Mail — and, once the share exists, manage or remove people. Create
/// the share with `SyncManager.makeShare()` first.
///
/// The delegate matters even though the recipient's Messages card renders from
/// the share's server-stored title/thumbnail: it is the ONLY signal when the
/// user taps the sheet's own "Stop Sharing" (owner) or "Remove Me"
/// (participant), which otherwise leaves the app's role and People list
/// pointing at a dead share.
struct CloudShareView: UIViewControllerRepresentable {
    let share: CKShare
    /// Invite card title, e.g. "Miller — Two of Us".
    var itemTitle: String = "Two of Us"
    /// Optional invite card thumbnail (the baby's avatar).
    var itemThumbnail: Data?

    func makeCoordinator() -> Coordinator {
        Coordinator(title: itemTitle, thumbnail: itemThumbnail)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: SyncConstants.container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let title: String
        private let thumbnail: Data?

        init(title: String, thumbnail: Data?) {
            self.title = title
            self.thumbnail = thumbnail
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { title }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? { thumbnail }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            // The share itself pre-exists (saved in makeShare); this fires for
            // participant/permission edits that failed. Nothing to roll back —
            // the sheet re-reads server truth next open.
            print("CloudKit share sheet failed to save share: \(error)")
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            Task { @MainActor in
                SyncManager.shared?.handleShareSheetStopped()
            }
        }
    }
}
