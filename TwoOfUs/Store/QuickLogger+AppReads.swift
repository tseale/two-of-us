import SwiftData

extension QuickLogger {
    /// The app process's read path. `make()` opens a brand-new
    /// `ModelContainer` on the App Group store — a schema build and SQLite
    /// open, tens of milliseconds — and the app used to pay that on every
    /// reminder re-arm, i.e. after every log, foreground and sync batch.
    /// The app already holds that same store open (`AppModelContainer.shared`),
    /// and a fresh `ModelContext` on it reads exactly the same saved data.
    ///
    /// A fresh context, never `mainContext`: some callers (the alarm
    /// reschedules) run off the main actor. App target only — the
    /// extensions have no `AppModelContainer` and keep `make()`. Reads only:
    /// the notification-action WRITES deliberately stay on `make()`.
    ///
    /// While the app is running on its in-memory emergency store
    /// (`isEphemeralFallback`), defer to `make()` so that case behaves
    /// exactly as before.
    static func forAppReads() -> QuickLogger? {
        let container = AppModelContainer.shared
        if AppModelContainer.isEphemeralFallback { return make() }
        return QuickLogger(context: ModelContext(container))
    }
}
