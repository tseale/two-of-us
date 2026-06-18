import UIKit
import SwiftUI
import UserNotifications
import UserNotificationsUI

/// Principal class for the notification content extension. Hosts the SwiftUI
/// `NotificationCardView` and refreshes it for whichever notification the system
/// hands us (matched by `UNNotificationExtensionCategory` in Info.plist).
final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private var host: UIHostingController<NotificationCardView>?

    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        let card = NotificationCardView(
            style: NotificationCardView.Style(categoryID: content.categoryIdentifier),
            title: content.title,
            message: content.body
        )

        if let host {
            host.rootView = card
        } else {
            let host = UIHostingController(rootView: card)
            host.view.backgroundColor = .clear
            host.view.translatesAutoresizingMaskIntoConstraints = false
            addChild(host)
            view.addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: view.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            host.didMove(toParent: self)
            self.host = host
        }
    }
}
