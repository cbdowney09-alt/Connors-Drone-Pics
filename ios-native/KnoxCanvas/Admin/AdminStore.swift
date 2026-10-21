import Foundation
import FirebaseFirestore

/// Every company, for the KnoxCanvas admin: approve requests, pause and resume teams.
/// Only works for accounts with an `admins/{uid}` doc (Firestore rules enforce it).
@MainActor @Observable
final class AdminStore {
    struct Row: Identifiable {
        let id: String
        var company: Company
        var members: Int?
        var pins: Int?
    }

    private(set) var rows: [Row] = []
    private(set) var loadError: String?
    private(set) var loaded = false
    let uid: String
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var counted = Set<String>()

    init(uid: String) { self.uid = uid }

    func start() {
        guard listener == nil else { return }
        listener = db.collection("companies").addSnapshotListener { [weak self] snap, error in
            guard let self else { return }
            loaded = true
            if let error { loadError = "Couldn\u{2019}t load companies (\(TeamStore.describe(error)))"; return }
            loadError = nil
            let old = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            rows = (snap?.documents ?? []).map { d in
                Row(id: d.documentID, company: Company(d.data(), fallbackName: "Unnamed company"),
                    members: old[d.documentID]?.members, pins: old[d.documentID]?.pins)
            }
            for r in rows where !counted.contains(r.id) { counted.insert(r.id); Task { await self.count(r.id) } }
            Task { await self.fillOwners() }
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    func rows(_ status: Company.Status) -> [Row] {
        rows.filter { $0.company.status == status }.sorted {
            status == .pending
                ? ($0.company.requestedAt ?? .distantPast) > ($1.company.requestedAt ?? .distantPast)
                : $0.company.name.localizedCompare($1.company.name) == .orderedAscending
        }
    }

    var pendingCount: Int { rows.filter { $0.company.status == .pending }.count }

    /// Team size and pin count, so you can see who's actually using it.
    private func count(_ id: String) async {
        let members = try? await db.collection("users").whereField("companyId", isEqualTo: id)
            .count.getAggregation(source: .server).count.intValue
        let pins = try? await db.collection("companies").document(id).collection("pins")
            .count.getAggregation(source: .server).count.intValue
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[i].members = members
        rows[i].pins = pins
    }

    /// Companies made before requests existed don't have the owner's name and email on them.
    private func fillOwners() async {
        for r in rows where r.company.ownerEmail.isEmpty && !r.company.ownerId.isEmpty {
            guard let d = try? await db.collection("users").document(r.company.ownerId).getDocument().data(),
                  let i = rows.firstIndex(where: { $0.id == r.id }) else { continue }
            rows[i].company.ownerName = d["name"] as? String ?? ""
            rows[i].company.ownerEmail = d["email"] as? String ?? ""
        }
    }

    func set(_ id: String, _ status: Company.Status) async throws {
        do {
            try await TeamStore.serverWrite {
                try await self.db.collection("companies").document(id).updateData([
                    "status": status.rawValue, "statusAt": FieldValue.serverTimestamp(), "statusBy": self.uid,
                ])
            }
        } catch let e as Friendly { throw e }
        catch { throw Friendly("Couldn\u{2019}t update (\(TeamStore.describe(error)))") }
    }
}
