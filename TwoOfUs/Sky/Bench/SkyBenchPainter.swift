import Foundation

/// The bench's one painter. Every picture the bench makes off the main
/// thread (a sky texture, the land's planes) is made through it, so only one
/// is ever being made, whichever screen asked.
///
/// The work runs in the task that asked for it; nothing here is detached. So
/// when SwiftUI cancels a `.task(id:)` (its slider has moved on, its screen
/// has gone), `Task.isCancelled` reads true inside the work, and the work can
/// stop where it stands. A request already cancelled when its turn comes does
/// no work at all.
///
/// Build 234 made each picture on a detached task of its own. A drag of the
/// Land screen's Hour slider started a whole paint for every value it passed,
/// six at a time, none of which could be stopped; the app ran out of memory
/// under them and crashed.
actor SkyBenchPainter {
    static let shared = SkyBenchPainter()

    /// Does `work` once nothing else is being done here, and gives back what
    /// it made: nil, without doing it, if the asking task has been cancelled
    /// by then.
    ///
    /// Not `async`, on purpose. With nowhere to suspend, no second piece of
    /// work can be let in while the first stands half done.
    func paint<Picture>(_ work: @Sendable () -> Picture?) -> Picture? {
        guard !Task.isCancelled else { return nil }
        return work()
    }
}
