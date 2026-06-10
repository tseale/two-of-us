import SwiftUI
import UIKit
import CloudKit

/// Presents the system share sheet (`UICloudSharingController`) for an already
/// prepared zone-wide `CKShare`, so the owner can invite the co-parent via
/// Messages/Mail. Create the share with `SyncManager.makeShare()` first.
struct CloudShareView: UIViewControllerRepresentable {
    let share: CKShare

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: SyncConstants.container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}
}
