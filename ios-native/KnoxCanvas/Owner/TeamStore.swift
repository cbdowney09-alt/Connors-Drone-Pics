import Foundation
import FirebaseFirestore

/// A row of `users` where companyId matches.
struct Member: Identifiable {
    let uid: String
    var name: String
    var email: String
    var role: String
    var id: String { uid }
    var display: String { name.isEmpty ? email : name }
}

/// Owner tools: team list, invite codes, company settings and metrics data.
/// Mirrors app.html's "Team & settings" and "Metrics" sections.
@MainActor @Observable
final class TeamStore {
    let companyId: String
    let uid: String
    private(set) var members: [Member] = []
    private(set) var shifts: [Shift] = []
    private(set) var loading = false
    private(set) var loadError: String?
    private let db = Firestore.firestore()

    init(companyId: String, uid: String) {
        self.companyId = companyId
        self.uid = uid
    }

    private var companyDoc: DocumentReference { db.collection("companies").document(companyId) }

    // MARK: Team

    static func fetchMembers(companyId: String) async throws -> [Member] {
        let snap = try await Firestore.firestore().collection("users").whereField("companyId", isEqualTo: companyId).getDocuments()
        let list = snap.documents.map { d in
            let p = d.data()
            return Member(uid: d.documentID, name: p["name"] as? String ?? "", email: p["email"] as? String ?? "",
                          role: p["role"] as? String ?? "employee")
        }
        // Owner first, then by name (the web's fetchMembers sort).
        return list.sorted {
            if ($0.role == "owner") != ($1.role == "owner") { return $0.role == "owner" }
            return $0.name.localizedCompare($1.name) == .orderedAscending
        }
    }

    func loadMembers() async {
        loading = true
        defer { loading = false }
        do { members = try await Self.fetchMembers(companyId: companyId); loadError = nil }
        catch { loadError = "Couldn\u{2019}t load team (\(Self.describe(error)))" }
    }

    /// Deleting the user doc is all the web does; they land on setup next time they open the app.
    func remove(_ m: Member) async throws {
        do { try await Self.serverWrite { try await self.db.collection("users").document(m.uid).delete() } }
        catch let e as Friendly { throw e }
        catch { throw Friendly("Couldn\u{2019}t remove (\(Self.describe(error)))") }
        members.removeAll { $0.uid == m.uid }
    }

    // MARK: Invites

    static func makeInviteCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var bytes = [UInt8](repeating: 0, count: 8)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = bytes.map { _ in UInt8.random(in: 0...255) }
        }
        // 256 is a multiple of 32, so `% count` isn't biased.
        return String(bytes.map { chars[Int($0) % chars.count] })
    }

    /// Writes `invites/{code}` and returns the code and its expiry.
    func createInvite(companyName: String) async throws -> (code: String, expires: Date) {
        let code = Self.makeInviteCode()
        let expires = Date().addingTimeInterval(TimeInterval(AppConfig.inviteDays) * 86_400)
        let data: [String: Any] = [
            "companyId": companyId, "companyName": companyName, "createdBy": uid,
            "createdAt": FieldValue.serverTimestamp(), "expiresAt": Timestamp(date: expires),
        ]
        do {
            try await Self.serverWrite { try await self.db.collection("invites").document(code).setData(data) }
        } catch let e as Friendly { throw e }
        catch { throw Friendly("Couldn\u{2019}t create invite (\(Self.describe(error)))") }
        return (code, expires)
    }

    static func inviteMessage(code: String, companyName: String) -> String {
        "Join \(companyName.isEmpty ? "our team" : companyName) on KnoxCanvas: open \(AppConfig.webAppURL), create an account, choose \"Join my team\", and enter code \(code)"
    }

    // MARK: Settings

    /// Validates like the web, then updates the company doc. Returns the saved values.
    /// `roofCutoff` is left as it is: the app no longer has a roofing mode, but the website still reads it.
    func saveSettings(name rawName: String, sheetsUrl rawUrl: String) async throws -> (String, String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let sheetsUrl = rawUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Friendly("Company name can\u{2019}t be empty") }
        if !sheetsUrl.isEmpty && !sheetsUrl.hasPrefix("https://") {
            throw Friendly("The Sheets URL must start with https://")
        }
        do { try await Self.serverWrite { try await self.companyDoc.updateData(["name": name, "sheetsUrl": sheetsUrl]) } }
        catch let e as Friendly { throw e }
        catch { throw Friendly("Couldn\u{2019}t save (\(Self.describe(error)))") }
        return (name, sheetsUrl)
    }

    // MARK: Metrics

    func loadMetrics() async {
        loading = true
        defer { loading = false }
        do {
            members = try await Self.fetchMembers(companyId: companyId)
            let snap = try await companyDoc.collection("shifts").getDocuments()
            shifts = snap.documents.map { Shift(id: $0.documentID, data: $0.data()) }.sorted { $0.clockIn > $1.clockIn }
            loadError = nil
        } catch { loadError = "Couldn\u{2019}t load metrics (\(Self.describe(error)))" }
    }

    /// Firestore's awaited writes only return once the server confirms, so with no signal
    /// they wait forever. Give up waiting after 12 s; the write stays queued on the device.
    static func serverWrite(_ write: @escaping @Sendable () async throws -> Void) async throws {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask { try await write(); return true }
            group.addTask { try await Task.sleep(for: .seconds(12)); return false }
            let finished = try await group.next() ?? false
            group.cancelAll()
            if !finished {
                throw Friendly("No connection. This is saved on the phone and will finish when you\u{2019}re back online.")
            }
        }
    }

    static func describe(_ error: Error) -> String {
        if let code = firestoreCode(error) {
            switch code {
            case .permissionDenied: return "permission denied"
            case .unavailable: return "offline"
            default: break
            }
        }
        return error.localizedDescription
    }
}

/// Same math as app.html's renderMetrics.
struct Metrics {
    enum Range: String, CaseIterable, Identifiable {
        case today, week, month, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .today: "Today"
            case .week: "This week"
            case .month: "This month"
            case .all: "All time"
            }
        }

        /// Start of the range in epoch ms; weeks start on Sunday like JS getDay().
        func since(now: Date = Date(), calendar: Calendar = .current) -> Int64 {
            let day = calendar.startOfDay(for: now)
            let start: Date
            switch self {
            case .today: start = day
            case .week:
                let back = calendar.component(.weekday, from: day) - 1 // 1 = Sunday
                start = calendar.date(byAdding: .day, value: -back, to: day) ?? day
            case .month:
                start = calendar.date(from: calendar.dateComponents([.year, .month], from: day)) ?? day
            case .all: return 0
            }
            return Int64(start.timeIntervalSince1970 * 1000)
        }
    }

    struct EmployeeRow: Identifiable {
        let member: Member
        let hangers: Int
        let hours: Double
        var id: String { member.uid }
    }

    let hangers: Int
    let interested: Int
    let hours: Double
    let shifts: [Shift]
    let breakdown: [EmployeeRow]

    /// `who` nil means everyone.
    init(pins: [Pin], shifts allShifts: [Shift], members: [Member], since: Int64, who: String?) {
        func match(_ u: String?) -> Bool { who == nil || u == who }
        func hangersFor(_ test: (String?) -> Bool) -> Int {
            pins.filter { p in
                p.status == .hanger && Self.ms(p.raw["hangerAt"], or: p.ts) >= since
                    && test((p.raw["hangerBy"] as? String) ?? (p.raw["updatedBy"] as? String))
            }.count
        }
        let fShifts = allShifts.filter { $0.clockIn >= since && match($0.userId) }
        hangers = hangersFor(match)
        interested = pins.filter { p in
            p.status == .interest && Self.ms(p.raw["statusAt"], or: p.ts) >= since
                && match((p.raw["statusBy"] as? String) ?? (p.raw["updatedBy"] as? String))
        }.count
        hours = Double(fShifts.reduce(0) { $0 + $1.durationMs }) / 3_600_000
        shifts = fShifts
        breakdown = who != nil ? [] : members.map { m in
            EmployeeRow(member: m, hangers: hangersFor { $0 == m.uid },
                        hours: Double(fShifts.filter { $0.userId == m.uid }.reduce(0) { $0 + $1.durationMs }) / 3_600_000)
        }
    }

    /// JS `a || b || 0` for epoch-ms fields.
    private static func ms(_ v: Any?, or fallback: Int64) -> Int64 {
        let n = (v as? NSNumber)?.int64Value ?? 0
        return n != 0 ? n : fallback
    }

    var perHour: String { hours > 0 ? String(format: "%.1f", Double(hangers) / hours) : "\u{2014}" }
    var perShift: String { shifts.isEmpty ? "\u{2014}" : String(Int((Double(hangers) / Double(shifts.count)).rounded())) }
    var hoursText: String { String(format: "%.1fh", hours) }
}
