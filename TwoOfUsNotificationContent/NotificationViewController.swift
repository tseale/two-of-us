import UIKit
import SwiftUI
import UserNotifications
import UserNotificationsUI

/// Principal class for the notification content extension. Hosts the SwiftUI
/// `NotificationCardView` and refreshes it for whichever notification the system
/// hands us (matched by `UNNotificationExtensionCategory` in Info.plist).
final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private var host: UIHostingController<NotificationCardView>?
    /// Lives as long as the drop-off card is up, so the system action row's
    /// typed note updates the same card.
    private var dropoffModel: DropoffCardModel?

    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        let style = NotificationCardView.Style(categoryID: content.categoryIdentifier)
        if style == .dropoffBoard {
            dropoffModel = DropoffCardModel(userInfo: content.userInfo)
        } else {
            dropoffModel = nil
        }
        let card = NotificationCardView(
            style: style,
            title: content.title,
            subtitle: content.subtitle,
            message: content.body,
            dropoff: dropoffModel
        )

        if let host {
            host.rootView = card
        } else {
            let host = UIHostingController(rootView: card)
            host.view.backgroundColor = .clear
            host.view.translatesAutoresizingMaskIntoConstraints = false
            // Report the SwiftUI content's own height so the notification
            // sizes to the card (the buttons made it taller than the fixed
            // initial ratio) instead of clipping.
            host.sizingOptions = .intrinsicContentSize
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

    /// System action-row taps while the card is showing. The drop-off card
    /// absorbs "Add a note" so the typed note lands on the Notes row with the
    /// card still up; everything else (Open in app, the pick-up marker,
    /// Log feed / Snooze on the other categories) is forwarded to the app's
    /// handler as before.
    func didReceive(_ response: UNNotificationResponse,
                    completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void) {
        if response.actionIdentifier == NotificationID.Action.addNote,
           let model = dropoffModel,
           let text = (response as? UNTextInputNotificationResponse)?.userText {
            model.addNote(text)
            completion(.doNotDismiss)
            return
        }
        completion(.dismissAndForwardAction)
    }
}
