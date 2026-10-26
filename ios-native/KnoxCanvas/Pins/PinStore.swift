import Foundation
import Network
import CoreLocation
import FirebaseFirestore

/// Live pins, plus every pin write. Mirrors app.html's data layer (subscribePins, savePin,
/// createPin, syncToSheets, neighborhood years).
///
/// Doorline crew can hang for several client businesses at once (`workIds`): each one's pins are
/// kept in `pinsBy`, the map shows the newest copy of each house, and every write goes to all of
/// them. Normally `workIds` is just the user's own company.
@MainActor @Observable
final class PinStore {
    enum Sync: Equatable { case ok, pending, offline, error }

    private(set) var pins: [String: Pin] = [:]
    /// Bumped on every snapshot so the map can diff cheaply.
    private(set) var version = 0
    private(set) var sync: Sync = .ok
    private(set) var zones: [YearZone] = []
    /// Bumped when zones change so the map redraws zone outlines.
    private(set) var zonesVersion = 0
    /// The most recent pins, set once after the first snapshot so the map can frame them.
    var initialFrame: [CLLocationCoordinate2D]?
    var hidden: Set<PinStatus> = []
    var routeStart: (coordinate: CLLocationCoordinate2D, addr: String)?
    var toast: ((String) -> Void)?

    /// The user's own company (team, metrics, settings).
    let companyId: String
    /// The companies whose pins this map shows and writes to.
    let workIds: [String]
    let uid: String
    var sheetsUrl: String

    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []
    private var pinsBy: [String: [String: Pin]] = [:]
    private var pendingIn = Set<String>()
    private var hasPendingWrites: Bool { !pendingIn.isEmpty }
    private var online = true
    private var listenError = false
    private let monitor = NWPathMonitor()
    private var didFrame = false

    init(companyId: String, workIds: [String] = [], uid: String, sheetsUrl: String) {
        self.companyId = companyId
        self.workIds = workIds.isEmpty ? [companyId] : workIds
        self.uid = uid
        self.sheetsUrl = sheetsUrl
    }

    /// The first company worked for: zones go there.
    var primaryId: String { workIds[0] }
    private func pinsCol(_ cid: String) -> CollectionReference { db.collection("companies").document(cid).collection("pins") }
    private var zonesDoc: DocumentReference {
        db.collection("companies").document(primaryId).collection("settings").document("neighborhoodYears")
    }

    func start() {
        guard listeners.isEmpty else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.online = path.status == .satisfied; self?.updateSync() }
        }
        monitor.start(queue: .global(qos: .utility))

        for cid in workIds {
            pinsBy[cid] = [:]
            listeners.append(pinsCol(cid).addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
                self?.received(cid, snap, error)
            })
        }
        Task { await loadZones() }
    }

    private func received(_ cid: String, _ snap: QuerySnapshot?, _ error: Error?) {
            if let error {
                print("pins listener:", error)
                listenError = true
                updateSync()
                toast?("Sync error: \(firestoreCode(error).map { "\($0.rawValue)" } ?? error.localizedDescription)")
                return
            }
            guard let snap else { return }
            listenError = false
            for ch in snap.documentChanges {
                let id = ch.document.documentID
                if ch.type == .removed { pinsBy[cid]?[id] = nil }
                else if let p = Pin(id: id, data: ch.document.data()) { pinsBy[cid]?[id] = p }
                merge(id)
            }
            if snap.metadata.hasPendingWrites { pendingIn.insert(cid) } else { pendingIn.remove(cid) }
            version &+= 1
            updateSync()
            if !didFrame && !pins.isEmpty {
                didFrame = true
                initialFrame = pins.values.sorted { $0.ts > $1.ts }.prefix(150).map(\.coordinate)
            }
    }

    /// The newest copy of a house across the companies worked for.
    private func merge(_ id: String) {
        pins[id] = workIds.compactMap { pinsBy[$0]?[id] }.max { $0.ts < $1.ts }
    }

    func stop() {
        listeners.forEach { $0.remove() }
        listeners = []
        monitor.cancel()
    }

    private func updateSync() {
        sync = listenError ? .error : hasPendingWrites ? .pending : online ? .ok : .offline
    }

    var counts: [PinStatus: Int] {
        var c: [PinStatus: Int] = [:]
        for p in pins.values { c[p.status, default: 0] += 1 }
        return c
    }

    // MARK: - Writes

    /// Merge-writes like the web's savePin. Doesn't wait for the server: Firestore queues the
    /// write offline and the snapshot listener shows it immediately.
    func save(_ id: String, _ data: [String: Any]) {
        for cid in workIds {
            // A company that doesn't have this house yet gets the whole pin, never a partial record.
            var d: [String: Any] = pinsBy[cid]?[id] == nil ? (pins[id]?.raw ?? [:]) : [:]
            d.merge(data) { $1 }
            d["updatedBy"] = uid
            d["updatedAt"] = FieldValue.serverTimestamp()
            pinsCol(cid).document(id).setData(d, merge: true) { [weak self] error in
                guard let error, let self else { return }
                print("save pin:", error)
                sync = .error
                toast?("Couldn\u{2019}t save (\(error.localizedDescription))")
            }
        }
    }

    /// Creates a `none` pin unless one already exists at this spot. Returns its ID.
    @discardableResult
    func createPin(at c: CLLocationCoordinate2D, addr: String? = nil) -> String {
        let id = Pin.makeId(lat: c.latitude, lng: c.longitude)
        guard pins[id] == nil else { return id }
        let now = nowMs()
        let data: [String: Any] = [
            "lat": c.latitude, "lng": c.longitude, "addr": addr ?? "Loading address\u{2026}",
            "status": PinStatus.none.rawValue, "note": "", "yearBuilt": yearForPoint(c),
            "ts": now, "createdBy": uid, "createdAt": now,
        ]
        if let p = Pin(id: id, data: data) { pins[id] = p; version &+= 1 }
        save(id, data)
        if addr == nil {
            Task {
                let a = await Geocoder.address(for: c)
                guard pins[id] != nil else { return }
                pins[id]?.addr = a
                pins[id]?.raw["addr"] = a
                version &+= 1
                save(id, ["addr": a])
            }
        }
        return id
    }

    func setStatus(_ id: String, _ status: PinStatus) {
        guard var p = pins[id] else { return }
        let now = nowMs()
        var upd: [String: Any] = ["status": status.rawValue, "ts": now, "statusBy": uid, "statusAt": now]
        if status == .hanger { upd["hangerBy"] = uid; upd["hangerAt"] = now }
        p.status = status
        p.ts = now
        p.raw.merge(upd) { $1 }
        pins[id] = p
        version &+= 1
        save(id, upd)
        syncUpsert(p)
    }

    func setNote(_ id: String, _ note: String) {
        pins[id]?.note = note
        pins[id]?.raw["note"] = note
        save(id, ["note": note])
    }

    func setYear(_ id: String, _ year: String) {
        pins[id]?.yearBuilt = year
        pins[id]?.raw["yearBuilt"] = year
        save(id, ["yearBuilt": year])
    }

    func delete(_ id: String) {
        pins[id] = nil
        version &+= 1
        for cid in workIds {
            pinsCol(cid).document(id).delete { [weak self] error in
                guard let error, let self else { return }
                sync = .error
                toast?("Couldn\u{2019}t delete (\(error.localizedDescription))")
            }
        }
        postToSheets(["action": "delete", "id": id])
    }

    /// True if a pin is within `within` meters (the web's nearestPin check).
    func hasPin(near lat: Double, _ lng: Double, within: Double) -> Bool {
        let c = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        return pins.values.contains { Geo.distance(c, $0.coordinate) < within }
    }

    /// Street sweep: writes the accepted houses as hanger pins with `source: 'gps-sweep'`
    /// in batches (like the web's placeSweepPins). Returns how many were placed.
    func createSweepPins(_ houses: [Candidate]) -> Int {
        let now = nowMs()
        var placed: [Pin] = []
        let per = max(1, 400 / workIds.count) // a batch holds 500 writes
        for chunkStart in stride(from: 0, to: houses.count, by: per) {
            let batch = db.batch()
            var any = false
            for c in houses[chunkStart..<min(chunkStart + per, houses.count)] {
                let id = Pin.makeId(lat: c.lat, lng: c.lng)
                if pins[id] != nil || hasPin(near: c.lat, c.lng, within: SWEEP.dupRadius) { continue }
                let coord = CLLocationCoordinate2D(latitude: c.lat, longitude: c.lng)
                let data: [String: Any] = [
                    "lat": c.lat, "lng": c.lng,
                    "addr": c.addr.isEmpty ? String(format: "%.4f, %.4f", c.lat, c.lng) : c.addr,
                    "status": PinStatus.hanger.rawValue, "note": "", "yearBuilt": yearForPoint(coord),
                    "ts": now, "createdBy": uid, "createdAt": now, "statusBy": uid, "statusAt": now,
                    "hangerBy": uid, "hangerAt": now, "source": "gps-sweep",
                ]
                guard let p = Pin(id: id, data: data) else { continue }
                pins[id] = p
                placed.append(p)
                var d = data
                d["updatedBy"] = uid
                d["updatedAt"] = FieldValue.serverTimestamp()
                for cid in workIds { batch.setData(d, forDocument: pinsCol(cid).document(id), merge: true) }
                any = true
            }
            guard any else { continue }
            batch.commit { [weak self] error in
                guard let error, let self else { return }
                print("sweep pins:", error)
                sync = .error
                toast?("Couldn\u{2019}t save street pins (\(error.localizedDescription))")
            }
        }
        version &+= 1
        placed.forEach(syncUpsert)
        return placed.count
    }

    // MARK: - Neighborhood years

    func yearForPoint(_ c: CLLocationCoordinate2D) -> String {
        zones.first { $0.contains(c) }?.year ?? ""
    }

    private func loadZones() async {
        do {
            let d = try await zonesDoc.getDocument()
            zones = ((d.data()?["zones"] as? [[String: Any]]) ?? []).map(YearZone.init)
            zonesVersion &+= 1
        } catch { print("zones:", error) }
    }

    /// "Apply year to nearby pins (400 m)": updates every pin in range and records a circle zone
    /// so new pins there get the year too. Returns the number of pins updated.
    func applyYearNearby(_ id: String, year: String) -> Int {
        guard let p = pins[id] else { return 0 }
        let radius = 400.0
        var count = 0
        for (pid, other) in pins where Geo.distance(p.coordinate, other.coordinate) <= radius {
            setYear(pid, year)
            count += 1
        }
        version &+= 1
        zones.removeAll { $0.polygon == nil && $0.center.map { Geo.distance(p.coordinate, $0) <= 200 } ?? false }
        zones.append(YearZone(["lat": p.lat, "lng": p.lng, "year": year, "radius": radius]))
        saveZones()
        return count
    }

    /// A drawn neighborhood: every pin inside gets the year. Points are stored as
    /// `{lat, lng}` maps because Firestore rejects nested arrays (the web's `[[lat, lng]]`
    /// form fails to save). Returns the number of pins updated.
    func addPolygonZone(name: String, year: String, polygon: [CLLocationCoordinate2D]) -> Int {
        var count = 0
        for (pid, p) in pins where Geo.pointInPolygon(p.coordinate, polygon) {
            setYear(pid, year)
            count += 1
        }
        version &+= 1
        zones.append(YearZone(["name": name, "year": year,
                               "polygon": polygon.map { ["lat": $0.latitude, "lng": $0.longitude] }]))
        saveZones()
        return count
    }

    private func saveZones() {
        zonesVersion &+= 1
        zonesDoc.setData(["zones": zones.map(\.raw)]) { [weak self] error in
            if let error { self?.toast?("Couldn\u{2019}t save zones (\(error.localizedDescription))") }
        }
    }

    // MARK: - Google Sheets

    /// Same as the web: only hanger pins are sent on upsert.
    private func syncUpsert(_ p: Pin) {
        guard p.status == .hanger else { return }
        var pin = p.raw.filter { JSONSerialization.isValidJSONObject([$0.value]) }
        pin["id"] = p.id
        pin["yearBuilt"] = p.yearBuilt
        postToSheets(["action": "upsert", "pin": pin])
    }

    private func postToSheets(_ body: [String: Any]) {
        guard !sheetsUrl.isEmpty, let url = URL(string: sheetsUrl),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        URLSession.shared.dataTask(with: req).resume()
    }
}
