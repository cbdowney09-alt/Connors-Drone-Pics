import Foundation
import FirebaseFirestore

/// `companies/{cid}/shifts/{auto}`
struct Shift: Identifiable {
    let id: String
    var clockIn: Int64
    var clockOut: Int64
    var durationMs: Int64
    var hangers: Int
    var hangersPerHour: Double
    var userId: String
    var userName: String

    init(id: String, data d: [String: Any]) {
        self.id = id
        userId = d["userId"] as? String ?? ""
        userName = d["userName"] as? String ?? ""
        clockIn = (d["clockIn"] as? NSNumber)?.int64Value ?? 0
        clockOut = (d["clockOut"] as? NSNumber)?.int64Value ?? clockIn
        durationMs = (d["durationMs"] as? NSNumber)?.int64Value ?? max(0, clockOut - clockIn)
        hangers = (d["hangers"] as? NSNumber)?.intValue ?? 0
        hangersPerHour = (d["hangersPerHour"] as? NSNumber)?.doubleValue ?? 0
    }
}

/// Clock in/out and shift history. Mirrors app.html's "Shifts / clock" section, plus the
/// active shift is also stored in Firestore (`users/{uid}.activeClockIn`) so it survives a
/// reinstall or sign-out (the web keeps it in localStorage only).
@MainActor @Observable
final class ShiftStore {
    private(set) var clockInTime: Int64?
    private(set) var shifts: [Shift] = []
    var toast: ((String) -> Void)?

    let companyId: String
    let uid: String
    var userName: String
    var sheetsUrl: String
    private let pins: PinStore
    /// Street sweep runs exactly while clocked in.
    let sweep: SweepTracker
    private let db = Firestore.firestore()

    /// Same limit as the web: a shift left open longer than this is dropped on restore.
    private static let maxShiftMs: Int64 = 16 * 3_600_000

    init(companyId: String, uid: String, userName: String, sheetsUrl: String, pins: PinStore) {
        self.companyId = companyId
        self.uid = uid
        self.userName = userName
        self.sheetsUrl = sheetsUrl
        self.pins = pins
        sweep = SweepTracker(uid: uid, pins: pins)
    }

    var clockedIn: Bool { clockInTime != nil }
    private var localKey: String { "knoxClock_\(uid)" }
    private var userDoc: DocumentReference { db.collection("users").document(uid) }
    private var shiftsCol: CollectionReference { db.collection("companies").document(companyId).collection("shifts") }

    func start() async {
        await restore()
        if let t = clockInTime { sweep.start(clockIn: t) }
        await loadShifts()
    }

    /// Signing out mid-shift: stop GPS but keep the trail on this device.
    func pause() { sweep.stop(keepSaved: true) }

    // MARK: Clock

    /// Uses whichever copy exists (device or Firestore), then makes both agree.
    private func restore() async {
        let local = (UserDefaults.standard.object(forKey: localKey) as? NSNumber)?.int64Value
        clockInTime = local.flatMap(fresh)
        if let t = clockInTime { sweep.start(clockIn: t) } // don't wait on the network to resume GPS
        let remote: Int64?
        do {
            let snap = try await userDoc.getDocument()
            remote = (snap.data()?["activeClockIn"] as? NSNumber)?.int64Value
        } catch {
            print("activeClockIn:", error)
            return // offline: keep the local copy
        }
        let t = local.flatMap(fresh) ?? remote.flatMap(fresh)
        clockInTime = t
        if let t { UserDefaults.standard.set(NSNumber(value: t), forKey: localKey) }
        else { UserDefaults.standard.removeObject(forKey: localKey) }
        if remote != t { writeRemote(t) }
    }

    private func fresh(_ t: Int64) -> Int64? { nowMs() - t < Self.maxShiftMs ? t : nil }

    private func writeRemote(_ t: Int64?) {
        userDoc.setData(["activeClockIn": t.map { $0 as Any } ?? FieldValue.delete()], merge: true) { error in
            // The device copy still works; this only matters after a reinstall.
            if let error { print("activeClockIn write:", error) }
        }
    }

    func clockIn() {
        let now = nowMs()
        clockInTime = now
        UserDefaults.standard.set(NSNumber(value: now), forKey: localKey)
        writeRemote(now)
        sweep.start(clockIn: now)
        toast?("Clocked in")
    }

    func clockOut() {
        guard let start = clockInTime else { return }
        let end = nowMs(), duration = end - start
        let hangers = hangersSince(start)
        let hours = Double(duration) / 3_600_000
        let perHour = hours > 0 ? (Double(hangers) / hours * 10).rounded() / 10 : 0
        let summary = sweep.shiftSummary(since: start)
        let data: [String: Any] = [
            "clockIn": start, "clockOut": end, "durationMs": duration, "hangers": hangers,
            // JS stores whole numbers as integers; match it so both apps write the same type.
            "hangersPerHour": perHour == perHour.rounded() ? NSNumber(value: Int(perHour)) : NSNumber(value: perHour),
            "userId": uid, "userName": userName,
            "trail": summary.trail, "trailMeters": summary.meters, "gpsHangers": gpsHangersSince(start),
        ]
        sweep.stop(keepSaved: false)
        let ref = shiftsCol.document()
        shifts.insert(Shift(id: ref.documentID, data: data), at: 0)
        clockInTime = nil
        UserDefaults.standard.removeObject(forKey: localKey)
        writeRemote(nil)
        toast?("Shift saved: \(hangers) hangers \u{00B7} \(Self.perHourText(perHour))/hr")
        ref.setData(data) { [weak self] error in
            if let error { self?.toast?("Shift couldn\u{2019}t sync (\(error.localizedDescription))") }
        }
        syncToSheets(data)
    }

    /// Hangers this user left since `since`, counted like the web's myShiftHangers.
    func hangersSince(_ since: Int64) -> Int {
        pins.pins.values.filter { p in
            guard p.status == .hanger else { return false }
            let by = (p.raw["hangerBy"] as? String) ?? (p.raw["updatedBy"] as? String)
            let at = (p.raw["hangerAt"] as? NSNumber)?.int64Value ?? (p.ts != 0 ? p.ts : 0)
            return by == uid && at >= since
        }.count
    }

    private func gpsHangersSince(_ since: Int64) -> Int {
        pins.pins.values.filter { p in
            p.raw["source"] as? String == "gps-sweep" && p.raw["hangerBy"] as? String == uid
                && ((p.raw["hangerAt"] as? NSNumber)?.int64Value ?? 0) >= since
        }.count
    }

    // MARK: History

    private func loadShifts() async {
        do {
            let snap = try await shiftsCol.whereField("userId", isEqualTo: uid).getDocuments()
            let loaded = snap.documents.map { Shift(id: $0.documentID, data: $0.data()) }
            // Keep any shift saved on this device that the query hasn't returned yet.
            let ids = Set(loaded.map(\.id))
            shifts = (loaded + shifts.filter { !ids.contains($0.id) }).sorted { $0.clockIn > $1.clockIn }
        } catch { print("shifts:", error) }
    }

    func csv() -> String {
        var lines = ["Date,Clock In,Clock Out,Duration,Hangers,Hangers Per Hour"]
        for s in shifts {
            lines.append([ShiftFormat.date(s.clockIn), ShiftFormat.time(s.clockIn), ShiftFormat.time(s.clockOut),
                          ShiftFormat.duration(s.durationMs), "\(s.hangers)", Self.perHourText(s.hangersPerHour)]
                .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    /// Like JS number printing: 3 → "3", 2.5 → "2.5".
    static func perHourText(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    // MARK: Sheets

    private func syncToSheets(_ d: [String: Any]) {
        guard !sheetsUrl.isEmpty, let url = URL(string: sheetsUrl) else { return }
        let start = (d["clockIn"] as? Int64) ?? 0, end = (d["clockOut"] as? Int64) ?? 0
        let body: [String: Any] = ["action": "shift", "shift": [
            "date": ShiftFormat.date(start), "clockIn": ShiftFormat.time(start), "clockOut": ShiftFormat.time(end),
            "duration": ShiftFormat.duration(end - start), "hangers": d["hangers"] ?? 0,
            "hangersPerHour": d["hangersPerHour"] ?? 0, "employee": userName,
        ]]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        URLSession.shared.dataTask(with: req).resume()
    }
}

/// Same output as app.html's formatDate / formatTime / formatDuration (en-US).
enum ShiftFormat {
    private static func formatter(_ f: String) -> DateFormatter {
        let d = DateFormatter()
        d.locale = Locale(identifier: "en_US_POSIX")
        d.dateFormat = f
        return d
    }
    private static let dateF = formatter("EEE, MMM d, yyyy")
    private static let timeF = formatter("h:mm a")

    static func date(_ ms: Int64) -> String { dateF.string(from: Date(timeIntervalSince1970: Double(ms) / 1000)) }
    static func time(_ ms: Int64) -> String { timeF.string(from: Date(timeIntervalSince1970: Double(ms) / 1000)) }

    /// "HH:MM:SS"
    static func duration(_ ms: Int64) -> String {
        let s = max(0, ms) / 1000
        return String(format: "%02lld:%02lld:%02lld", s / 3600, (s / 60) % 60, s % 60)
    }

    /// "H:MM" for the tab bar and shift chip.
    static func short(_ ms: Int64) -> String {
        let m = max(0, ms) / 60_000
        return String(format: "%lld:%02lld", m / 60, m % 60)
    }
}
