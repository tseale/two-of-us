import Foundation

/// Endpoint layout for Brightwheel's unofficial guardian API
/// (docs/BRIGHTWHEEL-INTEGRATION.md). Cookie-authenticated; paths live here so
/// a correction — most likely the v1→v2 migration visible in their web
/// bundle — is a one-line change, like `SnooAPIConfig`.
struct BrightwheelAPIConfig: Sendable {
    var baseURL = URL(string: "https://schools.mybrightwheel.com/api/v1")!
    static let signInURL = URL(string: "https://schools.mybrightwheel.com/sign-in")!
    static let cookieName = "_brightwheel_v2"
    var mePath = "/users/me"
    func studentsPath(guardianID: String) -> String { "/guardians/\(guardianID)/students" }
    func activitiesPath(studentID: String) -> String { "/students/\(studentID)/activities" }
    /// Honest User-Agent (same policy as SNOO). If the API turns out to gate
    /// on browser UAs this is the first knob to check — see the doc §5.
    var userAgent = "TwoOfUs-iOS (unofficial personal Brightwheel integration)"
}

enum BrightwheelAPIError: Error {
    case unauthorized
    case http(Int)
    case network(Error)
    case decoding

    var userMessage: String {
        switch self {
        case .unauthorized:
            "Brightwheel signed this session out. Reconnect to sign in again."
        case .http(let code):
            "Brightwheel returned an error (\(code)). Try again later."
        case .network:
            "Couldn't reach Brightwheel. Check your connection."
        case .decoding:
            "Brightwheel sent something unexpected — the API may have changed."
        }
    }
}

struct BrightwheelUser: Decodable, Sendable {
    let objectID: String
    let firstName: String?
    let lastName: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case objectID = "object_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case email
    }
}

struct BrightwheelStudent: Decodable, Sendable {
    let objectID: String
    let firstName: String?
    let lastName: String?

    enum CodingKeys: String, CodingKey {
        case objectID = "object_id"
        case firstName = "first_name"
        case lastName = "last_name"
    }

    var displayName: String {
        [firstName, lastName].compactMap(\.self).joined(separator: " ")
    }
}

/// Stateless network calls against the guardian API — the cookie is a
/// parameter, session state lives in `BrightwheelManager`. Read-only in v1.
/// Phase 1 deliberately returns activities as *raw JSON*: real response
/// shapes drive the DTOs we build next, not the other way around.
struct BrightwheelAPIClient: Sendable {
    var config = BrightwheelAPIConfig()
    var urlSession: URLSession = .shared

    func me(cookie: String) async throws -> BrightwheelUser {
        try decode(BrightwheelUser.self, from: try await get(config.mePath, cookie: cookie))
    }

    func students(cookie: String, guardianID: String) async throws -> [BrightwheelStudent] {
        struct Wrapper: Decodable {
            struct Entry: Decodable { let student: BrightwheelStudent }
            let students: [Entry]
        }
        let data = try await get(
            config.studentsPath(guardianID: guardianID), cookie: cookie,
            query: [URLQueryItem(name: "include[]", value: "schools")]
        )
        return try decode(Wrapper.self, from: data).students.map(\.student)
    }

    /// One page of activities for a single day, as typed DTOs — the sync
    /// path. 100 entries comfortably covers a daycare day.
    func activities(cookie: String, studentID: String, day: Date) async throws -> [BrightwheelActivity] {
        let data = try await activitiesData(cookie: cookie, studentID: studentID, day: day)
        return try decode(BrightwheelActivityPage.self, from: data).activities
    }

    /// The same fetch, pretty-printed for the debug console in Settings.
    func activitiesRawJSON(cookie: String, studentID: String, day: Date) async throws -> String {
        let data = try await activitiesData(cookie: cookie, studentID: studentID, day: day)
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: pretty, encoding: .utf8) else {
            return String(data: data, encoding: .utf8) ?? "<\(data.count) bytes, not UTF-8>"
        }
        return string
    }

    private func activitiesData(cookie: String, studentID: String, day: Date) async throws -> Data {
        let dayString = day.formatted(.iso8601.year().month().day())
        return try await get(
            config.activitiesPath(studentID: studentID), cookie: cookie,
            query: [
                URLQueryItem(name: "page", value: "0"),
                URLQueryItem(name: "page_size", value: "100"),
                URLQueryItem(name: "start_date", value: dayString),
                URLQueryItem(name: "end_date", value: dayString),
                URLQueryItem(name: "include_parent_actions", value: "false")
            ]
        )
    }

    private func get(_ path: String, cookie: String,
                     query: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(
            url: config.baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.setValue("\(BrightwheelAPIConfig.cookieName)=\(cookie)",
                         forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")
        // The shared URLSession would otherwise attach (and re-store) cookies
        // from its own jar; the Keychain session is the single source of truth.
        request.httpShouldHandleCookies = false

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw BrightwheelAPIError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw BrightwheelAPIError.decoding
        }
        switch http.statusCode {
        case 200...299: return data
        case 401, 403: throw BrightwheelAPIError.unauthorized
        default: throw BrightwheelAPIError.http(http.statusCode)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw BrightwheelAPIError.decoding }
    }
}
