import Foundation

#if DEBUG
/// Dev-only route discovery for the unofficial SNOO API (docs/SNOO-API.md).
/// Launch with `-snooRouteProbe` after signing in: fires one authenticated GET
/// per candidate session-history path using the stored token and logs status +
/// body prefix for each. Needed because unauthenticated probing can't prove a
/// route exists — the gateway rejects a bad token on the whole `/ss/me/...`
/// prefix before route matching, so only an authenticated request surfaces the
/// Express "Cannot GET" that marks a dead path.
enum SnooRouteProbe {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-snooRouteProbe") else { return }
        Task.detached { await run() }
    }

    private static func run() async {
        guard let tokens = SnooTokenStore().load(), let babyID = tokens.babyID else {
            AppLog.snoo.debug("PROBE aborted: no stored tokens/babyID — sign in first")
            return
        }
        let yesterday = Calendar.current.startOfDay(for: Date.now.addingTimeInterval(-86400))
        let local = SnooDates.queryString(from: yesterday)

        // `sessions/daily` signature recovered 2026-07-31 (timezone +
        // startTime + levels flags). Capture the full response shapes: with
        // and without detailedLevels, to see what that flag actually adds.
        let tz = TimeZone.current.identifier
        let daily = "/ss/me/v10/babies/\(babyID)/sessions/daily"
        let candidates: [(path: String, query: [URLQueryItem])] = [
            (daily, [.init(name: "timezone", value: tz),
                     .init(name: "startTime", value: local),
                     .init(name: "levels", value: "true"),
                     .init(name: "detailedLevels", value: "false")]),
            (daily, [.init(name: "timezone", value: tz),
                     .init(name: "startTime", value: local),
                     .init(name: "levels", value: "false"),
                     .init(name: "detailedLevels", value: "true")])
        ]

        AppLog.snoo.debug("PROBE start: \(candidates.count) candidates")
        for candidate in candidates {
            var components = URLComponents(string: "https://api-us-east-1-prod.happiestbaby.com")!
            components.path = candidate.path
            if !candidate.query.isEmpty { components.queryItems = candidate.query }
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(SnooAPIConfig().userAgent, forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 20
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                let body = String(data: data.prefix(6000), encoding: .utf8)?
                    .replacingOccurrences(of: "\n", with: " ") ?? "<non-UTF8>"
                AppLog.snoo.debug("PROBE \(candidate.path, privacy: .public) → \(status) body: \(body, privacy: .public)")
            } catch {
                AppLog.snoo.debug("PROBE \(candidate.path, privacy: .public) → transport error: \(String(describing: error), privacy: .public)")
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        AppLog.snoo.debug("PROBE done")
    }
}
#endif
