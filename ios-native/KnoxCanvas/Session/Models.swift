import Foundation
import FirebaseFirestore

/// `users/{uid}`
struct UserProfile {
    var name: String
    var email: String
    var role: String          // "owner" | "employee"
    var companyId: String?
    var companyName: String

    var isOwner: Bool { role == "owner" }

    init(_ d: [String: Any]) {
        name = d["name"] as? String ?? ""
        email = d["email"] as? String ?? ""
        role = d["role"] as? String ?? "employee"
        let cid = d["companyId"] as? String ?? ""
        companyId = cid.isEmpty ? nil : cid
        companyName = d["companyName"] as? String ?? ""
    }
}

/// `companies/{id}`
struct Company {
    /// New companies start `pending` until the KnoxCanvas admin approves them. Companies
    /// made before approvals existed have no status and count as active.
    enum Status: String { case pending, active, paused, declined }

    var name: String
    var ownerId: String
    var roofCutoff: Int
    var sheetsUrl: String
    var status: Status
    /// Contact details saved with the request (missing on older companies).
    var ownerName: String
    var ownerEmail: String
    var phone: String
    var requestedAt: Date?
    /// States the company works in ("TN"); every phone on the team downloads their house data.
    var states: [String]

    init(_ d: [String: Any], fallbackName: String = "Your company") {
        name = d["name"] as? String ?? fallbackName
        ownerId = d["ownerId"] as? String ?? ""
        roofCutoff = (d["roofCutoff"] as? NSNumber)?.intValue ?? AppConfig.defaultRoofCutoff
        sheetsUrl = d["sheetsUrl"] as? String ?? ""
        status = (d["status"] as? String).flatMap(Status.init) ?? .active
        ownerName = d["ownerName"] as? String ?? ""
        ownerEmail = d["ownerEmail"] as? String ?? ""
        phone = d["phone"] as? String ?? ""
        requestedAt = (d["requestedAt"] as? Timestamp)?.dateValue() ?? (d["createdAt"] as? Timestamp)?.dateValue()
        states = d["states"] as? [String] ?? []
    }
}
