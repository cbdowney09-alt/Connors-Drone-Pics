import Foundation

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
    var name: String
    var ownerId: String
    var roofCutoff: Int
    var sheetsUrl: String

    init(_ d: [String: Any], fallbackName: String = "Your company") {
        name = d["name"] as? String ?? fallbackName
        ownerId = d["ownerId"] as? String ?? ""
        roofCutoff = (d["roofCutoff"] as? NSNumber)?.intValue ?? AppConfig.defaultRoofCutoff
        sheetsUrl = d["sheetsUrl"] as? String ?? ""
    }
}
