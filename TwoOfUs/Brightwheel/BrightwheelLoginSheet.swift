import SwiftUI
import WebKit

/// Sign in to Brightwheel inside a real web view — their sign-in page runs
/// bot detection and sometimes 2FA, so we let the actual page handle all of
/// it and only harvest the resulting `_brightwheel_v2` cookie. The password
/// never touches our code (docs/BRIGHTWHEEL-INTEGRATION.md §1).
///
/// After every completed navigation the coordinator reads the cookie store;
/// each new cookie value is verified against `/users/me` before it counts as
/// signed in, because the page also sets cookies for anonymous visitors.
struct BrightwheelLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var manager = BrightwheelManager.shared
    @State private var isVerifying = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            BrightwheelWebView { cookie in
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
            let session = try await manager.completeSignIn(cookie: cookie)
            Haptics.success()
            errorMessage = nil
            _ = session
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

private struct BrightwheelWebView: UIViewRepresentable {
    /// Called with each new `_brightwheel_v2` value seen after a page load;
    /// returns true once one verifies, ending the watch.
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
        webView.load(URLRequest(url: BrightwheelAPIConfig.signInURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCookieCandidate: onCookieCandidate)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onCookieCandidate: (String) async -> Bool
        private var lastTriedCookie: String?
        private var finished = false
        private weak var webView: WKWebView?

        init(onCookieCandidate: @escaping (String) async -> Bool) {
            self.onCookieCandidate = onCookieCandidate
        }

        func attach(to webView: WKWebView) {
            self.webView = webView
        }

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in await self.harvestCookie() }
        }

        private func harvestCookie() async {
            guard !finished, let webView else { return }
            let cookies = await webView.configuration.websiteDataStore
                .httpCookieStore.allCookies()
            guard let cookie = cookies.first(where: {
                $0.name == BrightwheelAPIConfig.cookieName
                    && $0.domain.contains("mybrightwheel.com")
            }), cookie.value != lastTriedCookie else { return }
            lastTriedCookie = cookie.value
            finished = await onCookieCandidate(cookie.value)
        }
    }
}
