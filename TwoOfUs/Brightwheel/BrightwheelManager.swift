import Foundation
import Observation

/// The Brightwheel connection's runtime home: loads the Keychain session at
/// launch, finishes sign-in once the login web view surfaces a working cookie,
/// and runs the phase-1 debug fetch. Device-local by design — no CloudKit
/// blob until the shared-cookie question is answered
/// (docs/BRIGHTWHEEL-INTEGRATION.md §5); imported events would sync normally,
/// so one connected phone is enough for the household.
@Observable @MainActor
final class BrightwheelManager {
    static let shared = BrightwheelManager()

    private(set) var session: BrightwheelSession?
    private let store: BrightwheelSessionStore
    private let client: BrightwheelAPIClient

    init(store: BrightwheelSessionStore = BrightwheelSessionStore(),
         client: BrightwheelAPIClient = BrightwheelAPIClient()) {
        self.store = store
        self.client = client
        session = store.load()
    }

    var isConnected: Bool { session != nil }

    /// Called by the login sheet with a cookie candidate harvested from the
    /// web view. Verifies it against `/users/me` (the sign-in page sets
    /// cookies before authentication too, so possession alone proves nothing)
    /// and resolves the student roster. Throws `.unauthorized` for a
    /// not-actually-signed-in cookie — the sheet keeps waiting.
    func completeSignIn(cookie: String) async throws -> BrightwheelSession {
        let user = try await client.me(cookie: cookie)
        let students = try await client.students(cookie: cookie, guardianID: user.objectID)
        guard let student = students.first else {
            throw BrightwheelAPIError.decoding
        }
        let session = BrightwheelSession(
            cookie: cookie,
            email: user.email ?? "",
            guardianID: user.objectID,
            studentID: student.objectID,
            studentName: student.displayName,
            signedInAt: .now
        )
        store.save(session)
        self.session = session
        return session
    }

    func disconnect() {
        store.clear()
        session = nil
    }

    /// Phase-1 verification: today's report as raw JSON. A 401/403 clears
    /// nothing automatically — the cookie might be rate-limited rather than
    /// dead, and phase 1 is about *observing* behavior, not reacting to it.
    func fetchTodayRawJSON() async throws -> String {
        guard let session else { throw BrightwheelAPIError.unauthorized }
        return try await client.activitiesRawJSON(
            cookie: session.cookie, studentID: session.studentID, day: .now)
    }
}
