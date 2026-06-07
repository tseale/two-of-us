import WidgetKit
import SwiftUI

/// Widget bundle — registers all WidgetKit surfaces and the Sleep Live Activity.
@main
struct MillerTimeWidgetBundle: WidgetBundle {
    var body: some Widget {
        LockScreenFeedWidget()
        HomeScreenMediumWidget()
        HomeScreenLargeWidget()
        SleepLiveActivity()
    }
}
