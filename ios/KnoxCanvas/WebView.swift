import SwiftUI
import UIKit
import WebKit

/// Full-screen WKWebView that runs KnoxCanvas and wires up the native bridge.
struct KnoxWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()            // keeps login + offline Firestore cache between launches
        config.allowsInlineMediaPlayback = true

        let content = WKUserContentController()
        content.addUserScript(WKUserScript(source: BridgeScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        content.add(WeakMessageHandler(context.coordinator), name: "knox")
        config.userContentController = content

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = AppConfig.background
        webView.scrollView.backgroundColor = AppConfig.background
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never   // the page handles safe areas itself
        webView.allowsBackForwardNavigationGestures = false
        if #available(iOS 16.4, *) { webView.isInspectable = true }  // Safari → Develop menu for debugging

        context.coordinator.webView = webView
        LocationBridge.shared.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let url: URL
        weak var webView: WKWebView?
        private var triedCache = false

        init(url: URL) { self.url = url }

        // Messages from app.html: window.webkit.messageHandlers.knox.postMessage({ cmd: ... })
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let cmd = body["cmd"] as? String else { return }
            switch cmd {
            case "startTracking": LocationBridge.shared.pageStartedTracking()
            case "stopTracking":  LocationBridge.shared.pageStoppedTracking()
            case "geoStart":      LocationBridge.shared.geoStart()
            case "geoStop":       LocationBridge.shared.geoStop()
            case "googleSignIn":  startGoogleSignIn()
            case "googleFailed":
                showMessage("Google sign-in didn't finish (\((body["message"] as? String) ?? "unknown error")). Try again, or use email and password.")
            case "haptic":        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case "share":
                let name = (body["filename"] as? String) ?? "knoxcanvas.csv"
                let text = (body["text"] as? String) ?? ""
                shareFile(named: name, text: text)
            default: break
            }
        }

        // MARK: Navigation

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            LocationBridge.shared.pageWillLoad()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            triedCache = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            // Only react to real network failures (not cancelled loads or links we sent to Safari).
            let ns = error as NSError
            guard ns.domain == NSURLErrorDomain, ns.code != NSURLErrorCancelled else { return }
            // No signal: try the last copy of the page we have cached.
            if !triedCache {
                triedCache = true
                webView.load(URLRequest(url: url, cachePolicy: .returnCacheDataDontLoad))
                return
            }
            showOfflinePage(webView)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()   // iOS killed the page in the background; bring it back
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let target = action.request.url else { return decisionHandler(.allow) }
            // The web page's own Google flow (popup → redirect) can't work in an app; do it natively.
            if action.targetFrame?.isMainFrame == true && Self.isGoogleAuth(target) {
                startGoogleSignIn(); return decisionHandler(.cancel)
            }
            let scheme = target.scheme?.lowercased() ?? ""
            if ["tel", "mailto", "sms", "maps", "itms-apps"].contains(scheme) {
                UIApplication.shared.open(target); return decisionHandler(.cancel)
            }
            // Keep our own site and Firebase auth inside the app; open everything else (Zillow, etc.) in Safari.
            let host = target.host?.lowercased() ?? ""
            let appHost = url.host?.lowercased() ?? ""
            let isInternal = scheme == "about" || scheme == "data" || scheme == "blob" || host == appHost
                || host.hasSuffix(".firebaseapp.com") || host.hasSuffix(".web.app")
            if action.targetFrame?.isMainFrame == true && !isInternal {
                UIApplication.shared.open(target); return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        }

        // target="_blank" links (e.g. "View on Zillow") → Safari
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard let target = action.request.url, target.scheme?.hasPrefix("http") == true else { return nil }
            if Self.isGoogleAuth(target) { startGoogleSignIn() }   // Firebase's Google popup
            else { UIApplication.shared.open(target) }
            return nil
        }

        // MARK: alert() / confirm() / prompt() — WKWebView ignores these unless the app shows them

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            present(alert, orElse: completionHandler)
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            present(alert, orElse: { completionHandler(false) })
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
            present(alert, orElse: { completionHandler(nil) })
        }

        // MARK: Google sign-in

        /// Firebase's Google sign-in pages (popup or redirect) and Google's own login page.
        private static func isGoogleAuth(_ u: URL) -> Bool {
            let host = u.host?.lowercased() ?? ""
            return host == "accounts.google.com"
                || ((host.hasSuffix(".firebaseapp.com") || host.hasSuffix(".web.app")) && u.path.hasPrefix("/__/auth/"))
        }

        private func startGoogleSignIn() {
            GoogleSignIn.shared.signIn { [weak self] result in
                switch result {
                case .success(let t):
                    // Signs in to the page's Firebase instance (see BridgeScript), so any page version works.
                    self?.callPage("window.__knoxGoogleCredential", t.idToken, t.accessToken ?? "")
                case .failure(let e):
                    if let msg = e.errorDescription { self?.showMessage(msg) }
                }
            }
        }

        private func showMessage(_ text: String) {
            let alert = UIAlertController(title: "Google sign-in", message: text, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, orElse: {})
        }

        // MARK: Helpers

        /// Calls a page function with string arguments, safely JSON-encoded.
        private func callPage(_ fn: String, _ args: String...) {
            guard let data = try? JSONSerialization.data(withJSONObject: args),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView?.evaluateJavaScript("\(fn) && \(fn).apply(null, \(json)); true", completionHandler: nil)
        }

        private func shareFile(named name: String, text: String) {
            let safeName = name.replacingOccurrences(of: "/", with: "-")
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
            do { try text.write(to: fileURL, atomically: true, encoding: .utf8) } catch { return }
            let sheet = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            if let pop = sheet.popoverPresentationController, let view = webView {
                pop.sourceView = view
                pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            }
            present(sheet, orElse: {})
        }

        private func present(_ vc: UIViewController, orElse fallback: @escaping () -> Void) {
            guard let top = Self.topViewController() else { fallback(); return }
            top.present(vc, animated: true)
        }

        private static func topViewController() -> UIViewController? {
            let window = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
            var top = window?.rootViewController
            while let presented = top?.presentedViewController { top = presented }
            return top
        }

        private func showOfflinePage(_ webView: WKWebView) {
            let html = """
            <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <style>body{background:#0f1117;color:#f0f2ff;font-family:-apple-system;display:flex;flex-direction:column;
            align-items:center;justify-content:center;height:100vh;margin:0;padding:24px;text-align:center}
            button{margin-top:20px;background:#4f6ef7;color:#fff;border:none;border-radius:12px;padding:14px 28px;font-size:16px;font-weight:600}
            p{color:#8b90b0}</style></head><body>
            <h2>No connection</h2><p>KnoxCanvas needs a signal to open the first time. Your saved work is safe on this phone.</p>
            <button onclick="location.href='\(url.absoluteString)'">Try again</button></body></html>
            """
            triedCache = false
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
}

/// WKUserContentController holds its handlers strongly; this avoids a retain cycle.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
