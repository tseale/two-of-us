import SwiftUI
import WebKit

/// Sign in to Brightwheel inside a real web view — their sign-in page runs
/// bot detection and sometimes 2FA, so we let the actual page handle all of
/// it and only harvest the resulting `_brightwheel_v2` cookie. The password
/// never touches our code (docs/BRIGHTWHEEL-INTEGRATION.md §1).
///
/// The site is a SPA: after the sign-in form submits it swaps to the
/// dashboard client-side, so `didFinish` alone never sees the signed-in
/// state. The coordinator therefore harvests on every signal available —
/// navigation finishes, cookie-store changes, and SPA URL changes — and the
/// toolbar keeps a manual "Connect" as the fallback for anything all three
/// still miss. Each candidate cookie is verified against `/users/me` before
/// it counts, because the page sets cookies for anonymous visitors too.
struct BrightwheelLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var manager = BrightwheelManager.shared
    @State private var isVerifying = false
    @State private var errorMessage: String?
    @State private var checkNow = BrightwheelWebView.CheckTrigger()

    var body: some View {
        NavigationStack {
            BrightwheelWebView(checkTrigger: checkNow) { cookie in
                await verify(cookie: cookie)
            }
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .bottom) {
                if isVerifying || errorMessage != nil {
                    statusBar
                }
            }
            .navigationTitle("Connect Brightwheel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") { checkNow.fire() }
                        .disabled(isVerifying)
                }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if isVerifying {
                ProgressView().controlSize(.small)
                Text("Checking sign-in…")
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(AppColor.urgencyRed)
            }
        }
        .font(.footnote)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
        .padding(.bottom, 12)
    }

    /// Returns true when the cookie proved to be a signed-in session, which
    /// tells the web view to stop watching.
    private func verify(cookie: String) async -> Bool {
        isVerifying = true
        defer { isVerifying = false }
        do {
            _ = try await manager.completeSignIn(cookie: cookie)
            Haptics.success()
            errorMessage = nil
            dismiss()
            return true
        } catch BrightwheelAPIError.unauthorized {
            // Not signed in yet (anonymous cookie) — keep waiting quietly.
            return false
        } catch let error as BrightwheelAPIError {
            errorMessage = error.userMessage
            return false
        } catch {
            errorMessage = "Something went wrong. Try again."
            return false
        }
    }
}

struct BrightwheelWebView: UIViewRepresentable {
    /// Lets the sheet's "Connect" button reach into the coordinator for a
    /// forced re-check without the representable being recreated.
    @Observable @MainActor
    final class CheckTrigger {
        fileprivate weak var coordinator: Coordinator?
        func fire() {
            Task { await self.coordinator?.harvestCookie(force: true) }
        }
    }

    let checkTrigger: CheckTrigger
    /// Called with each `_brightwheel_v2` value worth trying; returns true
    /// once one verifies, ending the watch.
    let onCookieCandidate: (String) async -> Bool

    func makeUIView(context: Context) -> WKWebView {
        // Non-persistent: cookies live only inside this sheet, so a stale
        // browser session from a previous attempt can't shadow a fresh
        // sign-in, and nothing lingers on disk after the Keychain takes over.
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.attach(to: webView)
        checkTrigger.coordinator = context.coordinator
        webView.load(URLRequest(url: BrightwheelAPIConfig.signInURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCookieCandidate: onCookieCandidate)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        private let onCookieCandidate: (String) async -> Bool
        private var lastTriedCookie: String?
        private var finished = false
        private var inFlight = false
        private var retryQueued = false
        private weak var webView: WKWebView?
        private var urlObservation: NSKeyValueObservation?

        init(onCookieCandidate: @escaping (String) async -> Bool) {
            self.onCookieCandidate = onCookieCandidate
        }

        func attach(to webView: WKWebView) {
            self.webView = webView
            webView.configuration.websiteDataStore.httpCookieStore.add(self)
            // SPA route changes (sign-in → dashboard) update `url` without any
            // navigation-delegate callback — this observation is what actually
            // catches a successful login.
            urlObservation = webView.observe(\.url) { _, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.onSignedInPage else { return }
                    // Force: the login may upgrade the session server-side
                    // without changing the cookie's value.
                    await self.harvestCookie(force: true)
                }
            }
        }

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in await self.harvestCookie() }
        }

        nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            Task { @MainActor in await self.harvestCookie() }
        }

        /// True once the web view has left the sign-in page — the cue that a
        /// same-valued cookie is worth re-verifying.
        private var onSignedInPage: Bool {
            guard let path = webView?.url?.path() else { return false }
            return !path.contains("sign-in")
        }

        func harvestCookie(force: Bool = false) async {
            guard !finished, let webView else { return }
            // A signal landing during an in-flight verification (say, the SPA
            // finishing login while an anonymous cookie is mid-401) must not
            // be dropped — it may be the one that succeeds. Queue one retry.
            guard !inFlight else {
                retryQueued = true
                return
            }
            inFlight = true
            defer { inFlight = false }
            let cookies = await webView.configuration.websiteDataStore
                .httpCookieStore.allCookies()
            guard let cookie = cookies.first(where: {
                $0.name == BrightwheelAPIConfig.cookieName
                    && $0.domain.contains("mybrightwheel.com")
            }) else { return }
            // Off the sign-in page a same-valued cookie is still worth
            // re-verifying: login can upgrade the session server-side without
            // rotating the cookie.
            guard force || onSignedInPage || cookie.value != lastTriedCookie
            else { return }
            lastTriedCookie = cookie.value
            finished = await onCookieCandidate(cookie.value)
            if retryQueued {
                retryQueued = false
                if !finished {
                    inFlight = false
                    await harvestCookie(force: force)
                }
            }
        }
    }
}
