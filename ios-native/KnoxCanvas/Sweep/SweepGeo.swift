import Foundation

/// Tuning knobs, identical to app.html's SWEEP constant.
enum SWEEP {
    static let maxAcc = 35.0          // ignore GPS fixes worse than this (m)
    static let minStep = 6.0          // ignore jitter smaller than this (m)
    static let maxWalkSpeed = 3.5     // faster than ~8 mph = driving, not canvassing (m/s)
    static let lookupEvery = 120.0    // look up houses after this much walking (m)
    static let lookupMinMs: Int64 = 90_000 // ...or this long, if at least 40 m walked
    static let houseRadius = 45.0     // max distance from trail to a house (m)
    static let noStreetRadius = 32.0  // tighter radius for houses with no street tag (m)
    static let roadRadius = 25.0      // streets within this distance count as "walked" (m)
    static let dupRadius = 18.0       // an existing pin this close means the house is already pinned (m)

    /// iPhone app, areas with address tiles: a house counts once the walker comes within this
    /// distance of it (its address point, roughly the middle of the house). Set in the Shift screen.
    static let doorRadiusChoices: [Double] = [15, 20, 30, 45]
    static var doorRadius: Double {
        let v = UserDefaults.standard.double(forKey: "knoxDoorRadius")
        return v > 0 ? v : 20
    }
}

/// One GPS fix on the trail. `t` is epoch ms.
struct TrailPoint: Codable, Equatable {
    var lat: Double
    var lng: Double
    var t: Int64
}

struct LatLng {
    var lat: Double
    var lng: Double
}

/// The geometry helpers from app.html's street sweep, ported one for one.
enum SweepGeo {
    /// app.html's distBetween.
    static func dist(_ aLat: Double, _ aLng: Double, _ bLat: Double, _ bLng: Double) -> Double {
        let dy = (bLat - aLat) * 111_000
        let dx = (bLng - aLng) * 111_000 * cos(aLat * .pi / 180)
        return (dx * dx + dy * dy).squareRoot()
    }

    static func dist(_ a: LatLng, _ b: LatLng) -> Double { dist(a.lat, a.lng, b.lat, b.lng) }

    /// Distance (m) from a point to a polyline, using a local flat projection.
    static func distToLine(_ p: LatLng, _ line: [LatLng]) -> Double {
        guard !line.isEmpty else { return .infinity }
        if line.count == 1 { return dist(p, line[0]) }
        let kx = 111_320 * cos(p.lat * .pi / 180), ky = 110_540.0
        var best = Double.infinity
        for i in 1..<line.count {
            let ax = (line[i - 1].lng - p.lng) * kx, ay = (line[i - 1].lat - p.lat) * ky
            let bx = (line[i].lng - p.lng) * kx, by = (line[i].lat - p.lat) * ky
            let dx = bx - ax, dy = by - ay, len2 = dx * dx + dy * dy
            let t = len2 > 0 ? max(0, min(1, -(ax * dx + ay * dy) / len2)) : 0
            let x = ax + t * dx, y = ay + t * dy
            best = min(best, (x * x + y * y).squareRoot())
        }
        return best
    }

    static func lineLength(_ line: [LatLng]) -> Double {
        guard line.count > 1 else { return 0 }
        var d = 0.0
        for i in 1..<line.count { d += dist(line[i - 1], line[i]) }
        return d
    }

    /// Keep at most `max` vertices so Overpass queries stay short.
    static func thin<T>(_ line: [T], _ maxCount: Int) -> [T] {
        guard line.count > maxCount else { return line }
        let step = Double(line.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { line[Int((Double($0) * step).rounded())] }
    }

    /// Points every `every` meters along a line (for the geocoding fallback).
    static func samplesAlong(_ line: [LatLng], every: Double, maxCount: Int) -> [LatLng] {
        guard let first = line.first else { return [] }
        var out = [first]
        var carry = 0.0
        var i = 1
        while i < line.count && out.count < maxCount {
            let a = line[i - 1], b = line[i], d = dist(a, b)
            var pos = every - carry
            while pos <= d && out.count < maxCount {
                let t = pos / d
                out.append(LatLng(lat: a.lat + (b.lat - a.lat) * t, lng: a.lng + (b.lng - a.lng) * t))
                pos += every
            }
            carry = (carry + d).truncatingRemainder(dividingBy: every)
            i += 1
        }
        return out
    }

    private static let streetAbbr: [String: String] = [
        "street": "st", "avenue": "ave", "road": "rd", "drive": "dr", "lane": "ln", "court": "ct", "circle": "cir",
        "boulevard": "blvd", "place": "pl", "parkway": "pkwy", "pike": "pk", "highway": "hwy", "terrace": "ter",
        "trail": "trl", "north": "n", "south": "s", "east": "e", "west": "w", "northeast": "ne", "northwest": "nw",
        "southeast": "se", "southwest": "sw", "point": "pt", "cove": "cv", "hollow": "holw", "ridge": "rdg",
        "heights": "hts", "crossing": "xing", "square": "sq",
    ]

    /// "North Main Street" and "N Main St" both become "n main st".
    static func normStreet(_ s: String) -> String {
        s.lowercased()
            .filter { !".,#'".contains($0) }
            .split(whereSeparator: \.isWhitespace)
            .map { streetAbbr[String($0)] ?? String($0) }
            .joined(separator: " ")
    }
}

extension TrailPoint {
    var ll: LatLng { LatLng(lat: lat, lng: lng) }
}
