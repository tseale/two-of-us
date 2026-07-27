import Foundation

/// Endpoint layout for the unofficial Happiest Baby API — the current
/// (post-Aug-2025) generation: AWS Cognito auth + `api-us-east-1-prod` REST.
/// Everything is derived from community clients (docs/SNOO-API.md); the
/// session paths are best-candidates and unverified against the live service,
/// so they all live here where a correction is a one-line change.
struct SnooAPIConfig: Sendable {
    var cognitoURL = URL(string: "https://cognito-idp.us-east-1.amazonaws.com/")!
    /// The Happiest Baby app's public Cognito app-client id (hardcoded the
    /// same way in python-snoo — it is not a secret).
    var cognitoClientID = "6kqofhc8hm394ielqdkvli0oea"

    var baseURL = URL(string: "https://api-us-east-1-prod.happiestbaby.com")!
    var devicesPath = "/hds/me/v11/devices"
    var babiesPath = "/us/me/v10/babies"
    func lastSessionPath(babyID: String) -> String {
        "/ss/me/v10/babies/\(babyID)/sessions/last"
    }
    func aggregatedPath(babyID: String) -> String {
        "/ss/v2/babies/\(babyID)/sessions/aggregated/"
    }

    /// Honest User-Agent (§10) — no impersonation of the official app.
    var userAgent = "TwoOfUs-iOS (unofficial personal SNOO integration)"
}

/// All network I/O for the SNOO integration. An actor: token refresh is
/// single-flight (concurrent callers await the same in-flight refresh task)
/// and token state can't race. Read-only against the API in v1 (§2.2).
actor SnooAPIClient {
    private let config: SnooAPIConfig
    private let tokenStore: SnooTokenStore
    private let urlSession: URLSession
    private var refreshTask: Task<SnooTokens, Error>?

    init(config: SnooAPIConfig = SnooAPIConfig(),
         tokenStore: SnooTokenStore = SnooTokenStore(),
         urlSession: URLSession = .shared) {
        self.config = config
        self.tokenStore = tokenStore
        self.urlSession = urlSession
    }

    // MARK: Auth (Cognito USER_PASSWORD_AUTH — docs/SNOO-API.md §A.1)

    /// Signs in and resolves the account's baby id in one go. The password is
    /// used for this single request and discarded — never persisted (§5).
    func logIn(email: String, password: String) async throws -> SnooTokens {
        let payload: [String: Any] = [
            "AuthParameters": ["USERNAME": email, "PASSWORD": password],
            "AuthFlow": "USER_PASSWORD_AUTH",
            "ClientId": config.cognitoClientID
        ]
        var tokens = try await cognitoAuth(payload: payload, email: email,
                                           existingRefreshToken: nil)
        // Resolve the baby id now so every later sync is exactly 3 requests.
        // Best-effort: a failure here still leaves the account connected.
        tokens.babyID = try? await resolveBabyID(accessToken: tokens.accessToken)
        tokenStore.save(tokens)
        return tokens
    }

    /// Clears the persisted tokens. (State reset happens in the coordinator.)
    func signOut() {
        tokenStore.clear()
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Returns live tokens: refreshes proactively when the stored ones expire
    /// within 5 minutes. Single-flight — concurrent callers share one refresh.
    private func validTokens() async throws -> SnooTokens {
        guard let tokens = tokenStore.load() else { throw SnooAPIError.needsReauth }
        guard tokens.needsRefresh else { return tokens }
        return try await refresh(tokens)
    }

    private func refresh(_ tokens: SnooTokens) async throws -> SnooTokens {
        if let inFlight = refreshTask {
            return try await inFlight.value
        }
        let task = Task<SnooTokens, Error> { [config] in
            guard let refreshToken = tokens.refreshToken else { throw SnooAPIError.needsReauth }
            let payload: [String: Any] = [
                "AuthParameters": ["REFRESH_TOKEN": refreshToken],
                "AuthFlow": "REFRESH_TOKEN_AUTH",
                "ClientId": config.cognitoClientID
            ]
            do {
                var refreshed = try await cognitoAuth(payload: payload, email: tokens.email,
                                                      existingRefreshToken: refreshToken)
                refreshed.babyID = tokens.babyID
                tokenStore.save(refreshed)
                return refreshed
            } catch SnooAPIError.invalidCredentials {
                // A dead refresh token means the user signs in again (§5):
                // clear so the Settings row flips to "Sign in again".
                tokenStore.clear()
                throw SnooAPIError.needsReauth
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    /// One Cognito round-trip (login or refresh — same URL, same shape).
    private func cognitoAuth(payload: [String: Any], email: String,
                             existingRefreshToken: String?) async throws -> SnooTokens {
        var request = URLRequest(url: config.cognitoURL)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        request.setValue("AWSCognitoIdentityProviderService.InitiateAuth",
                         forHTTPHeaderField: "x-amz-target")
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await send(request)
        // Cognito reports bad credentials as HTTP 400 + "__type":
        // "NotAuthorizedException" — not a 401.
        guard response.statusCode == 200 else {
            switch response.statusCode {
            case 400, 401, 403: throw SnooAPIError.invalidCredentials
            case 429: throw SnooAPIError.rateLimited(retryAfter: response.retryAfter)
            default: throw SnooAPIError.server(status: response.statusCode)
            }
        }
        do {
            let dto = try JSONDecoder().decode(CognitoAuthResponseDTO.self, from: data)
            guard let result = dto.AuthenticationResult, let idToken = result.IdToken else {
                throw SnooAPIError.invalidCredentials
            }
            return SnooTokens(
                accessToken: idToken,   // the IdToken is what the REST API wants
                // Refresh responses usually omit the refresh token — keep the old one.
                refreshToken: result.RefreshToken ?? existingRefreshToken,
                expiresAt: Date.now.addingTimeInterval(result.ExpiresIn ?? 3600),
                email: email,
                babyID: nil
            )
        } catch let error as SnooAPIError {
            throw error
        } catch {
            throw SnooAPIError.decoding(underlying: error, endpoint: "cognito")
        }
    }

    // MARK: Devices / baby

    func fetchDevices() async throws -> [SnooDevice] {
        let data = try await get(path: config.devicesPath)
        do {
            let dto = try JSONDecoder().decode(SnooDeviceListDTO.self, from: data)
            return (dto.snoo ?? []).compactMap { device in
                device.serialNumber.map {
                    SnooDevice(serialNumber: $0, babyID: device.babyIds?.first)
                }
            }
        } catch {
            throw SnooAPIError.decoding(underlying: error, endpoint: config.devicesPath)
        }
    }

    /// Devices → babyIds is authoritative; the babies list is the fallback.
    private func resolveBabyID(accessToken: String) async throws -> String {
        if let fromDevices = try await fetchDevices().compactMap(\.babyID).first {
            return fromDevices
        }
        let data = try await get(path: config.babiesPath)
        do {
            let babies = try JSONDecoder().decode([SnooBabyDTO].self, from: data)
            guard let id = babies.first?._id else { throw SnooAPIError.noDeviceOnAccount }
            return id
        } catch let error as SnooAPIError {
            throw error
        } catch {
            throw SnooAPIError.decoding(underlying: error, endpoint: config.babiesPath)
        }
    }

    /// The cached baby id, resolving (and re-persisting) it if sign-in
    /// couldn't. Throws `noDeviceOnAccount` when the account truly has none.
    private func babyID() async throws -> String {
        var tokens = try await validTokens()
        if let id = tokens.babyID { return id }
        let id = try await resolveBabyID(accessToken: tokens.accessToken)
        tokens.babyID = id
        tokenStore.save(tokens)
        return id
    }

    // MARK: Sessions

    /// The most recent (possibly still-running) session. Authoritative for
    /// in-progress detection (§7).
    func fetchLastSession() async throws -> SnooSession? {
        let path = config.lastSessionPath(babyID: try await babyID())
        let data = try await get(path: path)
        do {
            let dto = try JSONDecoder().decode(SnooLastSessionDTO.self, from: data)
            return SnooSessionNormaliser.session(fromLast: dto)
        } catch {
            throw SnooAPIError.decoding(underlying: error, endpoint: path)
        }
    }

    /// The aggregated day starting at `dayStart` (local midnight), flattened
    /// into completed sessions.
    func fetchAggregatedSessions(dayStart: Date) async throws -> [SnooSession] {
        let path = config.aggregatedPath(babyID: try await babyID())
        let query = [URLQueryItem(name: "startTime", value: SnooDates.queryString(from: dayStart))]
        let data = try await get(path: path, query: query)
        do {
            let dto = try JSONDecoder().decode(SnooAggregatedDayDTO.self, from: data)
            return SnooSessionNormaliser.sessions(fromAggregated: dto)
        } catch {
            throw SnooAPIError.decoding(underlying: error, endpoint: path)
        }
    }

    // MARK: Requests

    private func get(path: String, query: [URLQueryItem] = []) async throws -> Data {
        let tokens = try await validTokens()
        var request = makeRequest(path: path, query: query)
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")

        var (data, response) = try await send(request)
        // On 401, one refresh + one retry — never more (§9). The API has also
        // been seen using 403 for expired tokens (pysnoo2), so treat it the same.
        if response.statusCode == 401 || response.statusCode == 403 {
            let refreshed = try await refresh(tokens)
            request.setValue("Bearer \(refreshed.accessToken)", forHTTPHeaderField: "Authorization")
            (data, response) = try await send(request)
        }
        switch response.statusCode {
        case 200: return data
        case 401, 403: throw SnooAPIError.needsReauth
        case 402: throw SnooAPIError.subscriptionRequired
        case 429: throw SnooAPIError.rateLimited(retryAfter: response.retryAfter)
        default: throw SnooAPIError.server(status: response.statusCode)
        }
    }

    private func makeRequest(path: String, query: [URLQueryItem] = []) -> URLRequest {
        var components = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SnooAPIError.server(status: -1)
            }
            // Log status only — never bodies, tokens, or credentials (§5).
            AppLog.snoo.debug("SNOO \(request.url?.path ?? "?", privacy: .public) → \(http.statusCode)")
            return (data, http)
        } catch let error as SnooAPIError {
            throw error
        } catch {
            throw SnooAPIError.transport(underlying: error)
        }
    }
}

private extension HTTPURLResponse {
    var retryAfter: TimeInterval? {
        (value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
    }
}
