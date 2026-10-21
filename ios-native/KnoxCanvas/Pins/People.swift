import SwiftUI

/// How pins are colored on the map.
enum ColorBy: String { case status, person }

extension Pin {
    /// Who is behind the pin's current status: who hung the hanger, who marked it
    /// interested / not interested / do not return, or who dropped it (not visited).
    /// Older pins without these fields fall back to `updatedBy`.
    var personId: String? {
        func s(_ k: String) -> String? { (raw[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        switch status {
        case .hanger: return s("hangerBy") ?? s("statusBy") ?? s("updatedBy") ?? s("createdBy")
        case .none: return s("createdBy") ?? s("updatedBy")
        default: return s("statusBy") ?? s("updatedBy") ?? s("createdBy")
        }
    }

    /// When that happened (epoch ms), 0 if unknown.
    var personAt: Int64 {
        func n(_ k: String) -> Int64 { (raw[k] as? NSNumber)?.int64Value ?? 0 }
        let t: Int64
        switch status {
        case .hanger: t = n("hangerAt")
        case .none: t = 0
        default: t = n("statusAt")
        }
        return t != 0 ? t : ts
    }
}

/// Company members, a stable color for each, and which people are hidden in person view.
@MainActor @Observable
final class People {
    /// Key for pins with no known person.
    static let unknown = ""
    static let unknownColor = Color(hex: 0x6b7280)
    /// Distinct on the dark map and from each other; the status colors are not on screen in
    /// person view, so reusing their hues is fine.
    static let palette: [UInt32] = [
        0x3b82f6, 0xec4899, 0x22c55e, 0xf97316, 0xa855f7, 0xeab308,
        0x06b6d4, 0xef4444, 0x84cc16, 0x6366f1, 0xf43f5e, 0x14b8a6,
    ]

    let uid: String
    private let selfName: String
    private(set) var members: [Member] = []
    /// False when this account can't list company members (Firestore rules); names then
    /// show as "Teammate".
    private(set) var membersLoaded = false
    private(set) var order: [String] = []
    private(set) var version = 0
    var hidden: Set<String> = [] { didSet { version &+= 1 } }

    init(uid: String, selfName: String) {
        self.uid = uid
        self.selfName = selfName
    }

    func load(companyId: String) async {
        do {
            members = try await TeamStore.fetchMembers(companyId: companyId)
            membersLoaded = true
        } catch {
            print("people:", error)
        }
        reorder(seen: Set(order))
    }

    /// Colors go to members first (owner, then by name) so they stay put as pins change,
    /// then to anyone else found on pins (people who have left), by ID.
    func update(from pins: [String: Pin]) {
        var seen = Set<String>()
        for p in pins.values { if let id = p.personId { seen.insert(id) } }
        if !seen.isSubset(of: Set(order)) { reorder(seen: seen.union(order)) }
    }

    private func reorder(seen: Set<String>) {
        var o = members.map(\.uid)
        if !o.contains(uid) { o.insert(uid, at: 0) }
        o += seen.subtracting(o).sorted()
        order = o
        version &+= 1
    }

    func key(_ p: Pin) -> String { p.personId ?? Self.unknown }

    func color(_ key: String) -> Color {
        guard key != Self.unknown, let i = order.firstIndex(of: key) else { return Self.unknownColor }
        return Color(hex: Self.palette[i % Self.palette.count])
    }

    func name(_ key: String) -> String {
        if key == Self.unknown { return "Unknown" }
        if let m = members.first(where: { $0.uid == key }) { return m.display }
        if key == uid { return selfName.isEmpty ? "You" : selfName }
        return membersLoaded ? "Former member" : "Teammate"
    }

    /// Chip label: "You" for yourself.
    func shortName(_ key: String) -> String { key == uid ? "You" : name(key) }

    func toggle(_ key: String) {
        if hidden.contains(key) { hidden.remove(key) } else { hidden.insert(key) }
    }
}
