import Foundation

/// Emails the admin about a new company request through a Google Apps Script web app
/// (same idea as the Sheets webhook). Fire and forget: the request is already saved in
/// Firestore and shows in the Admin screen either way.
enum RequestNotifier {
    static func send(company: String, companyId: String, owner: String, email: String, phone: String) {
        guard !AppConfig.requestWebhook.isEmpty, let url = URL(string: AppConfig.requestWebhook) else { return }
        let body: [String: Any] = ["action": "companyRequest", "company": company, "companyId": companyId,
                                   "owner": owner, "email": email, "phone": phone, "source": "iOS app"]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        // text/plain avoids a CORS preflight on the web; Apps Script reads the raw body either way.
        req.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        URLSession.shared.dataTask(with: req).resume()
    }
}
