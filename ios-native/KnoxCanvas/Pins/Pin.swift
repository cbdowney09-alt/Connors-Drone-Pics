import Foundation
import CoreLocation

/// `companies/{cid}/pins/{lat6,lng6}`. Mirrors app.html's normalizePin.
struct Pin: Identifiable, Equatable {
    let id: String
    var lat: Double
    var lng: Double
    var addr: String
    var status: PinStatus
    var note: String
    /// Stored as a string by the web (it comes from an <input>); older records may hold a number.
    var yearBuilt: String
    var ts: Int64
    /// The document as stored, so Sheets sync can send every field like the web does.
    var raw: [String: Any]

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lng) }

    static func == (a: Pin, b: Pin) -> Bool {
        a.id == b.id && a.lat == b.lat && a.lng == b.lng && a.addr == b.addr && a.status == b.status
            && a.note == b.note && a.yearBuilt == b.yearBuilt && a.ts == b.ts
    }

    /// Returns nil for records without usable coordinates (the web skips those too).
    init?(id: String, data d: [String: Any]) {
        guard let lat = Self.double(d["lat"]), let lng = Self.double(d["lng"]),
              lat.isFinite, lng.isFinite else { return nil }
        self.id = id
        self.lat = lat
        self.lng = lng
        addr = d["addr"] as? String ?? ""
        status = PinStatus(rawValue: d["status"] as? String ?? "") ?? .none
        note = d["note"] as? String ?? ""
        switch d["yearBuilt"] {
        case let s as String: yearBuilt = s
        case let n as NSNumber: yearBuilt = n.intValue == 0 ? "" : String(n.intValue)
        default: yearBuilt = ""
        }
        ts = (d["ts"] as? NSNumber)?.int64Value ?? 0
        raw = d
    }

    /// Same as the web's `lat.toFixed(6) + ',' + lng.toFixed(6)`. Both round the exact
    /// binary value, so the IDs match character for character.
    static func makeId(lat: Double, lng: Double) -> String {
        String(format: "%.6f,%.6f", lat, lng)
    }

    private static func double(_ v: Any?) -> Double? {
        switch v {
        case let n as NSNumber: n.doubleValue
        case let s as String: Double(s)
        default: nil
        }
    }
}

/// `companies/{cid}/settings/neighborhoodYears` → `zones[]`. Either a circle
/// (`lat, lng, radius`) or a polygon of `[lat, lng]` points.
struct YearZone {
    var year: String
    var name: String
    var center: CLLocationCoordinate2D?
    var radius: Double?
    var polygon: [CLLocationCoordinate2D]?
    var raw: [String: Any]

    init(_ d: [String: Any]) {
        raw = d
        year = (d["year"] as? String) ?? (d["year"] as? NSNumber).map { String($0.intValue) } ?? ""
        name = d["name"] as? String ?? ""
        if let lat = (d["lat"] as? NSNumber)?.doubleValue, let lng = (d["lng"] as? NSNumber)?.doubleValue {
            center = .init(latitude: lat, longitude: lng)
        }
        radius = (d["radius"] as? NSNumber)?.doubleValue
        // Accept [[lat, lng]] (what the web builds) and [{lat, lng}] (what Firestore can store).
        if let pts = d["polygon"] as? [Any] {
            let coords: [CLLocationCoordinate2D] = pts.compactMap { p in
                if let a = p as? [NSNumber], a.count >= 2 { return .init(latitude: a[0].doubleValue, longitude: a[1].doubleValue) }
                if let o = p as? [String: Any], let la = (o["lat"] as? NSNumber)?.doubleValue,
                   let ln = (o["lng"] as? NSNumber)?.doubleValue { return .init(latitude: la, longitude: ln) }
                return nil
            }
            polygon = coords.count >= 3 ? coords : nil
        }
    }

    func contains(_ c: CLLocationCoordinate2D) -> Bool {
        if let polygon { return Geo.pointInPolygon(c, polygon) }
        if let center, let radius { return Geo.distance(c, center) <= radius }
        return false
    }
}

enum Geo {
    /// Same flat-earth approximation as app.html's distBetween (meters).
    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let dy = (b.latitude - a.latitude) * 111_000
        let dx = (b.longitude - a.longitude) * 111_000 * cos(a.latitude * .pi / 180)
        return (dx * dx + dy * dy).squareRoot()
    }

    static func pointInPolygon(_ p: CLLocationCoordinate2D, _ poly: [CLLocationCoordinate2D]) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let xi = poly[i].latitude, yi = poly[i].longitude, xj = poly[j].latitude, yj = poly[j].longitude
            if (yi > p.longitude) != (yj > p.longitude),
               p.latitude < (xj - xi) * (p.longitude - yi) / (yj - yi) + xi { inside.toggle() }
            j = i
        }
        return inside
    }
}

func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
