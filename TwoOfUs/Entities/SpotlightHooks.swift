import Foundation

/// The call sites' view of the Spotlight indexer. This file compiles on every
/// toolchain — the iOS 27 fence lives INSIDE, so EventStore/AppDelegate can
/// call it unconditionally and stable-toolchain builds get a no-op.
enum SpotlightHooks {
    /// Something in the event log changed (local write, sync arrival, or a
    /// settings flip) — schedule a debounced reindex on iOS 27.
    static func eventsDidChange() {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            SpotlightIndexer.requestReindex()
        }
        #endif
    }
}
