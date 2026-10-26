import Foundation
import MapKit
import FirebaseFirestore

/// Doorline Hangers: a client's routes (the zip codes and neighborhoods they want hung) and the
/// crew's walk paths. Mirrors app.html's "Doorline Hangers" section.
///
/// Routes live in `companies/{cid}/settings/areas` →
/// `{ list: [{ id, kind: "zip", zip, name } | { id, kind: "draw", name, points: [{lat, lng}] }] }`.
/// A crew member hanging for several clients sees all of their routes; only the client edits them.
@MainActor @Observable
final class DoorlineStore {
    struct Area: Identifiable {
        let id: String
        /// The company the route belongs to.
        let cid: String
        let kind: String
        let zip: String
        let name: String
        let raw: [String: Any]
        var isZip: Bool { kind == "zip" }
    }

    private(set) var areas: [Area] = []
    /// Outlines by area id: the zip's Census boundary, or the drawn neighborhood.
    private(set) var shapes: [String: [MKPolygon]] = [:]
    /// Bumped when routes or outlines change, so the map redraws them.
    private(set) var version = 0
    private(set) var paths: [[CLLocationCoordinate2D]] = []
    private(set) var pathsVersion = 0
    private(set) var loadingZip: String?

    let workIds: [String]
    let uid: String
    private let db = Firestore.firestore()
    private var zipShapes: [String: [MKPolygon]] = [:]

    init(workIds: [String], uid: String) {
        self.workIds = workIds
        self.uid = uid
    }

    private var primaryId: String { workIds[0] }
    private func areasDoc(_ cid: String) -> DocumentReference {
        db.collection("companies").document(cid).collection("settings").document("areas")
    }

    // MARK: Routes

    func load() async {
        var all: [Area] = []
        for cid in workIds {
            do {
                let list = (try await areasDoc(cid).getDocument().data()?["list"] as? [[String: Any]]) ?? []
                all += list.compactMap { Self.area($0, cid: cid) }
            } catch { print("areas:", error) }
        }
        areas = all
        for a in areas where !a.isZip { shapes[a.id] = Self.drawnShape(a.raw) }
        version &+= 1
        for a in areas where a.isZip { await loadShape(a) }
    }

    private static func area(_ d: [String: Any], cid: String) -> Area? {
        guard let id = d["id"] as? String else { return nil }
        let kind = d["kind"] as? String ?? "draw"
        let zip = d["zip"] as? String ?? ""
        return Area(id: id, cid: cid, kind: kind, zip: zip, name: d["name"] as? String ?? (kind == "zip" ? zip : "Neighborhood"), raw: d)
    }

    private static func drawnShape(_ d: [String: Any]) -> [MKPolygon] {
        let pts = ((d["points"] as? [[String: Any]]) ?? []).compactMap { p -> CLLocationCoordinate2D? in
            guard let lat = (p["lat"] as? NSNumber)?.doubleValue, let lng = (p["lng"] as? NSNumber)?.doubleValue else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        return pts.count >= 3 ? [MKPolygon(coordinates: pts, count: pts.count)] : []
    }

    private func loadShape(_ a: Area) async {
        if let s = zipShapes[a.zip] { shapes[a.id] = s; version &+= 1; return }
        guard let polys = await ZipBoundary.fetch(a.zip), !polys.isEmpty else { return }
        zipShapes[a.zip] = polys
        shapes[a.id] = polys
        version &+= 1
    }

    /// Returns a message for the toast.
    func addZip(_ raw: String) async -> String {
        let zip = raw.trimmingCharacters(in: .whitespaces)
        guard zip.count == 5, zip.allSatisfy(\.isASCII), zip.allSatisfy(\.isNumber) else { return "Enter a 5-digit zip code" }
        guard !areas.contains(where: { $0.isZip && $0.zip == zip }) else { return "\(zip) is already a route" }
        let d: [String: Any] = ["id": Self.newId(), "kind": "zip", "zip": zip, "name": zip, "addedAt": nowMs(), "addedBy": uid]
        guard let a = Self.area(d, cid: primaryId) else { return "Couldn\u{2019}t add \(zip)" }
        areas.append(a)
        version &+= 1
        save()
        loadingZip = zip
        await loadShape(a)
        loadingZip = nil
        return shapes[a.id] == nil ? "\(zip) is saved, but its boundary didn\u{2019}t load. It\u{2019}ll show on the map later." : "\(zip) added"
    }

    /// A drawn neighborhood. Points are `{lat, lng}` maps: Firestore rejects nested arrays.
    func addDrawn(name: String, points: [CLLocationCoordinate2D]) {
        let d: [String: Any] = ["id": Self.newId(), "kind": "draw", "name": name,
                                "points": points.map { ["lat": $0.latitude, "lng": $0.longitude] },
                                "addedAt": nowMs(), "addedBy": uid]
        guard let a = Self.area(d, cid: primaryId) else { return }
        areas.append(a)
        shapes[a.id] = Self.drawnShape(d)
        version &+= 1
        save()
    }

    func remove(_ id: String) {
        areas.removeAll { $0.id == id }
        shapes[id] = nil
        version &+= 1
        save()
    }

    var drawnCount: Int { areas.filter { !$0.isZip }.count }

    private func save() {
        let list = areas.filter { $0.cid == primaryId }.map(\.raw)
        areasDoc(primaryId).setData(["list": list, "updatedAt": FieldValue.serverTimestamp(), "updatedBy": uid]) { error in
            if let error { print("save areas:", error) }
        }
    }

    private static func newId() -> String { String(nowMs(), radix: 36) }

    func bounds(_ a: Area) -> MKMapRect? {
        guard let polys = shapes[a.id], !polys.isEmpty else { return nil }
        return polys.reduce(MKMapRect.null) { $0.union($1.boundingMapRect) }
    }

    var allBounds: MKMapRect? {
        let r = areas.compactMap(bounds).reduce(MKMapRect.null) { $0.union($1) }
        return r.isNull ? nil : r
    }

    /// Door hangers inside the route. Before a zip's outline loads, goes by the zip in the address.
    func count(_ a: Area, in pins: [Pin]) -> Int {
        guard let polys = shapes[a.id] else {
            return a.isZip ? pins.filter { $0.addr.contains(a.zip) }.count : 0
        }
        return pins.filter { p in
            let mp = MKMapPoint(p.coordinate)
            return polys.contains { Self.contains($0, mp) }
        }.count
    }

    nonisolated static func contains(_ poly: MKPolygon, _ p: MKMapPoint) -> Bool {
        guard poly.boundingMapRect.contains(p) else { return false }
        func inRing(_ g: MKMultiPoint) -> Bool {
            let pts = g.points(), n = g.pointCount
            var inside = false
            var j = n - 1
            for i in 0..<n {
                let a = pts[i], b = pts[j]
                if (a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
                j = i
            }
            return inside
        }
        return inRing(poly) && !(poly.interiorPolygons ?? []).contains { inRing($0) }
    }

    // MARK: Walk paths

    /// Loads the crew's GPS trails from this company's shifts. Returns a message for the toast.
    func showPaths() async -> String {
        do {
            let snap = try await db.collection("companies").document(primaryId).collection("shifts").getDocuments()
            let shifts = snap.documents.map { Shift(id: $0.documentID, data: $0.data()) }.sorted { $0.clockIn > $1.clockIn }
            let walks = shifts.prefix(150).map { Self.segments($0.trail) }.filter { !$0.isEmpty }
            paths = walks.flatMap { $0 }
            pathsVersion &+= 1
            return walks.isEmpty ? "No walk paths yet" : "Showing \(walks.count) walk\(walks.count == 1 ? "" : "s")"
        } catch {
            return "Couldn\u{2019}t load walk paths (\(TeamStore.describe(error)))"
        }
    }

    func hidePaths() {
        paths = []
        pathsVersion &+= 1
    }

    /// "lat,lng,seconds;…" → walked stretches. Split wherever the pace is faster than walking,
    /// so drives between streets don't show as walked.
    nonisolated static func segments(_ trail: String) -> [[CLLocationCoordinate2D]] {
        var out: [[CLLocationCoordinate2D]] = [], cur: [CLLocationCoordinate2D] = []
        var prev: (c: CLLocationCoordinate2D, t: Double)?
        for part in trail.split(separator: ";") {
            let f = part.split(separator: ",").compactMap { Double($0) }
            guard f.count >= 2, f[0].isFinite, f[1].isFinite else { continue }
            let c = CLLocationCoordinate2D(latitude: f[0], longitude: f[1]), t = f.count > 2 ? f[2] : .nan
            if let prev {
                let d = Geo.distance(prev.c, c), dt = t - prev.t
                if dt > 0 ? d / dt > 4 : d > 150 {
                    if cur.count > 1 { out.append(cur) }
                    cur = []
                }
            }
            cur.append(c)
            prev = (c, t)
        }
        if cur.count > 1 { out.append(cur) }
        return out
    }
}
