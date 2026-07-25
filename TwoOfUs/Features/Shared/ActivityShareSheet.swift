import SwiftUI
import UIKit

/// Plain system share sheet (`UIActivityViewController`) for items that are
/// fetched asynchronously — `ShareLink` needs its item up front, which doesn't
/// fit "prepare the CloudKit share, then offer its URL" flows like resending
/// an invite link.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
