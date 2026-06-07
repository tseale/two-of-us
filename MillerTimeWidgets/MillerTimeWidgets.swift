import WidgetKit
import SwiftUI

/// Widget bundle — registers all WidgetKit surfaces and the Sleep Live Activity.
@main
struct MillerTimeWidgetBundle: WidgetBundle {
    var body: some Widget {
        LastFeedWidget()
        LastSleepWidget()
        LastDiaperWidget()
        DayRibbonWidget()
        NextFeedGaugeWidget()
        HomeScreenMediumWidget()
        HomeScreenLargeWidget()
        SleepLiveActivity()
    }
}
