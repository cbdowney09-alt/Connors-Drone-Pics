import SwiftUI
import MapKit

/// State for the map tools: zone drawing, the route optimizer, showing saved zones and zip
/// boundaries. Mirrors app.html's "Zone drawing", "Route optimizer" and
/// "Zip code overlay" sections. Each group has its own version so the map only redraws
/// what changed.
@MainActor @Observable
final class MapTools {
    // MARK: Drawing

    /// `area`: a Doorline client outlining a neighborhood they want hung.
    enum Drawing: Equatable { case off, zone, route, area }
    private(set) var drawing = Drawing.off
    private(set) var drawn: [CLLocationCoordinate2D] = []
    private(set) var drawVersion = 0

    func startDrawing(forRoute: Bool) { startDrawing(forRoute ? .route : .zone) }

    func startDrawing(_ mode: Drawing) {
        drawing = mode
        drawn = []
        drawVersion &+= 1
    }

    func stopDrawing() {
        drawing = .off
        drawn = []
        drawVersion &+= 1
    }

    func addPoint(_ c: CLLocationCoordinate2D) {
        drawn.append(c)
        drawVersion &+= 1
    }

    func undoPoint() {
        guard !drawn.isEmpty else { return }
        drawn.removeLast()
        drawVersion &+= 1
    }

    var drawStatus: String {
        switch drawn.count {
        case 0: "Tap the map to start"
        case 1, 2: "\(drawn.count) point\(drawn.count == 1 ? "" : "s") \u{2014} need at least 3"
        default: "\(drawn.count) points \u{2014} ready to save"
        }
    }

    // MARK: Route

    struct Stop: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
        let addr: String
    }

    private(set) var routeZone: [CLLocationCoordinate2D]?
    private(set) var route: [Stop] = []
    /// The start the current route was built from (the pin store's start can change after).
    private(set) var routeFrom: Stop?
    private(set) var routeFallback = false
    private(set) var routing = false
    private(set) var routeVersion = 0
    var skipVisited = true
    var skipDnr = true

    func setRouteZone(_ poly: [CLLocationCoordinate2D], pins: PinStore) {
        routeZone = poly
        if pins.routeStart == nil {
            let r = Self.bounds(poly)
            pins.routeStart = (CLLocationCoordinate2D(latitude: (r.minLat + r.maxLat) / 2, longitude: (r.minLng + r.maxLng) / 2), "Zone center")
        }
        routeVersion &+= 1
    }

    func clearRoute(pins: PinStore) {
        pins.routeStart = nil
        routeZone = nil
        route = []
        routeFrom = nil
        routeFallback = false
        routeVersion &+= 1
    }

    /// Returns a message for the toast.
    func generateRoute(pins: PinStore) async -> String {
        guard let start = pins.routeStart else { return "Draw a zone or set a start pin first" }
        routing = true
        defer { routing = false }
        let zone = routeZone
        var houses = await RouteFinder.houses(around: start.coordinate, in: zone)
        let fallback = houses == nil
        if houses == nil {
            houses = pins.pins.values
                .filter { p in zone.map { Geo.pointInPolygon(p.coordinate, $0) } ?? (Geo.distance(start.coordinate, p.coordinate) <= 800) }
                .map { Stop(coordinate: $0.coordinate, addr: $0.addr) }
        }
        let all = Array(pins.pins.values)
        let stops = (houses ?? []).filter { h in
            guard let ex = RouteFinder.nearestPin(h.coordinate, in: all) else { return true }
            if skipDnr && ex.status == .dnr { return false }
            if skipVisited && ex.status != .none { return false }
            return true
        }
        guard !stops.isEmpty else {
            return fallback ? "Map data unavailable and no unvisited saved pins here" : "No houses found in this area"
        }
        let from = Stop(coordinate: start.coordinate, addr: start.addr)
        route = RouteFinder.nearestNeighbor(from: from.coordinate, stops)
        routeFrom = from
        routeFallback = fallback
        routeVersion &+= 1
        return "Route: \(route.count) houses"
    }

    /// Meters from the previous stop (or the start) to stop `i`.
    func leg(_ i: Int) -> Double {
        guard let from = routeFrom, i < route.count else { return 0 }
        return Geo.distance(i == 0 ? from.coordinate : route[i - 1].coordinate, route[i].coordinate)
    }

    var routeTotal: Double { route.indices.reduce(0) { $0 + leg($1) } }

    nonisolated static func formatDistance(_ d: Double) -> String {
        d < 1000 ? "\(Int(d.rounded())) m" : String(format: "%.2f km", d / 1000)
    }

    // MARK: Saved neighborhood zones

    /// Shows drawn zones on the map. (Replaces the web's roofing target mode; the app is no
    /// longer roofing-specific.)
    var showZones = false

    // MARK: Zip boundaries

    struct Zip: Identifiable {
        let code: String
        let color: UIColor
        let polygons: [MKPolygon]
        var visible = true
        var id: String { code }
    }

    private(set) var zips: [Zip] = []
    private(set) var loadingZip: String?
    private(set) var zipVersion = 0
    private var zipColorIdx = 0
    static let zipColors: [UInt32] = [0x4f6ef7, 0x10b981, 0xf59e0b, 0x7c3aed, 0xef4444, 0x06b6d4]

    /// Returns an error for the toast, or nil when added.
    func addZip(_ raw: String) async -> String? {
        let zip = raw.trimmingCharacters(in: .whitespaces)
        guard zip.count == 5, zip.allSatisfy(\.isASCII), zip.allSatisfy(\.isNumber) else { return "Enter a 5-digit zip code" }
        guard !zips.contains(where: { $0.code == zip }), loadingZip == nil else { return "Already added" }
        loadingZip = zip
        defer { loadingZip = nil }
        guard let polys = await ZipBoundary.fetch(zip), !polys.isEmpty else { return "Couldn\u{2019}t find a boundary for \(zip)" }
        let color = UIColor(Color(hex: Self.zipColors[zipColorIdx % Self.zipColors.count]))
        zipColorIdx += 1
        zips.append(Zip(code: zip, color: color, polygons: polys))
        zipVersion &+= 1
        return nil
    }

    func toggleZip(_ code: String) {
        guard let i = zips.firstIndex(where: { $0.code == code }) else { return }
        zips[i].visible.toggle()
        zipVersion &+= 1
    }

    func removeZip(_ code: String) {
        zips.removeAll { $0.code == code }
        zipVersion &+= 1
    }

    // MARK: Helpers

    nonisolated static func bounds(_ pts: [CLLocationCoordinate2D]) -> (minLat: Double, minLng: Double, maxLat: Double, maxLng: Double) {
        let la = pts.map(\.latitude), lo = pts.map(\.longitude)
        return (la.min() ?? 0, lo.min() ?? 0, la.max() ?? 0, lo.max() ?? 0)
    }
}

/// Overpass lookups and the nearest-neighbor ordering for the route optimizer.
enum RouteFinder {
    /// Houses with an address inside the zone (or within 800 m of the start): our address
    /// tiles first, then Overpass. Nil if neither answered, so the caller can fall back to
    /// saved pins.
    static func houses(around c: CLLocationCoordinate2D, in zone: [CLLocationCoordinate2D]?) async -> [MapTools.Stop]? {
        let hasZone = (zone?.count ?? 0) >= 3
        let b: (minLat: Double, minLng: Double, maxLat: Double, maxLng: Double)
        if hasZone, let zone {
            b = MapTools.bounds(zone)
        } else {
            let dLat = 800 / 111_000.0, dLng = 800 / (111_000.0 * cos(c.latitude * .pi / 180))
            b = (c.latitude - dLat, c.longitude - dLng, c.latitude + dLat, c.longitude + dLng)
        }
        if let tiles = await AddressTiles.shared.addresses(minLat: b.minLat, minLng: b.minLng, maxLat: b.maxLat, maxLng: b.maxLng) {
            return tiles.compactMap { h in
                let p = CLLocationCoordinate2D(latitude: h.lat, longitude: h.lng)
                if hasZone, let zone, !Geo.pointInPolygon(p, zone) { return nil }
                if !hasZone, Geo.distance(c, p) > 800 { return nil }
                return MapTools.Stop(coordinate: p, addr: h.addr)
            }
        }
        let area = hasZone
            ? "(\(b.minLat),\(b.minLng),\(b.maxLat),\(b.maxLng))"
            : "(around:800,\(c.latitude),\(c.longitude))"
        let q = "[out:json][timeout:20];(node[\"addr:housenumber\"]\(area);way[\"addr:housenumber\"]\(area););out center;"
        guard let els = await HouseFinder.overpassRace(q, deadline: 12) else { return nil }
        return els.compactMap { el in
            guard let la = el.lat, let lo = el.lon else { return nil }
            let p = CLLocationCoordinate2D(latitude: la, longitude: lo)
            if let zone, zone.count >= 3, !Geo.pointInPolygon(p, zone) { return nil }
            let num = el.tags["addr:housenumber"] ?? "", street = el.tags["addr:street"] ?? ""
            let addr = !num.isEmpty && !street.isEmpty ? "\(num) \(street)" : String(format: "%.4f, %.4f", la, lo)
            return MapTools.Stop(coordinate: p, addr: addr)
        }
    }

    /// The saved pin within 18 m, like the web's nearestPin.
    static func nearestPin(_ c: CLLocationCoordinate2D, in pins: [Pin]) -> Pin? {
        var best: Pin?
        var bd = 18.0
        for p in pins {
            let d = Geo.distance(c, p.coordinate)
            if d < bd { bd = d; best = p }
        }
        return best
    }

    static func nearestNeighbor(from start: CLLocationCoordinate2D, _ stops: [MapTools.Stop]) -> [MapTools.Stop] {
        var remaining = stops
        var route: [MapTools.Stop] = []
        var current = start
        while !remaining.isEmpty {
            var bi = 0, bd = Double.infinity
            for (i, s) in remaining.enumerated() {
                let d = Geo.distance(current, s.coordinate)
                if d < bd { bd = d; bi = i }
            }
            let next = remaining.remove(at: bi)
            route.append(next)
            current = next.coordinate
        }
        return route
    }
}

/// Census TIGERweb first, then the OSM postal_code relation (same as the web).
enum ZipBoundary {
    static func fetch(_ zip: String) async -> [MKPolygon]? {
        if let p = await tiger(zip), !p.isEmpty { return p }
        return await overpass(zip)
    }

    private static func tiger(_ zip: String) async -> [MKPolygon]? {
        let s = "https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/PUMA_TAD_TAZ_UGA_ZCTA/MapServer/1/query?where=ZCTA5%3D%27\(zip)%27&outFields=ZCTA5&returnGeometry=true&outSR=4326&f=geojson"
        guard let url = URL(string: s) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else { return nil }
        var out: [MKPolygon] = []
        for f in features {
            guard let g = f["geometry"] as? [String: Any], let type = g["type"] as? String else { continue }
            switch type {
            case "Polygon":
                if let rings = g["coordinates"] as? [[[Double]]], let p = polygon(rings) { out.append(p) }
            case "MultiPolygon":
                for rings in (g["coordinates"] as? [[[[Double]]]]) ?? [] { if let p = polygon(rings) { out.append(p) } }
            default: break
            }
        }
        return out
    }

    /// GeoJSON rings are [lng, lat]; the first is the outline, the rest are holes.
    private static func polygon(_ rings: [[[Double]]]) -> MKPolygon? {
        func coords(_ ring: [[Double]]) -> [CLLocationCoordinate2D] {
            ring.compactMap { $0.count >= 2 ? CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) : nil }
        }
        guard let outer = rings.first.map(coords), outer.count >= 3 else { return nil }
        let holes = rings.dropFirst().map(coords).filter { $0.count >= 3 }.map { MKPolygon(coordinates: $0, count: $0.count) }
        return MKPolygon(coordinates: outer, count: outer.count, interiorPolygons: holes)
    }

    private struct Geom: Decodable { let lat: Double; let lon: Double }
    private struct Member: Decodable { let type: String; let geometry: [Geom]? }
    private struct Rel: Decodable { let members: [Member]? }
    private struct Resp: Decodable { let elements: [Rel]? }

    /// The web joins every member way into one ring; good enough to see the area.
    private static func overpass(_ zip: String) async -> [MKPolygon]? {
        let q = "[out:json][timeout:20];relation[\"postal_code\"=\"\(zip)\"][\"boundary\"=\"postal_code\"];out geom;"
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        let body = "data=" + (q.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        for ep in HouseFinder.overpass.prefix(2) {
            var req = URLRequest(url: URL(string: ep)!)
            req.httpMethod = "POST"
            req.timeoutInterval = 20
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data(body.utf8)
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let r = try? JSONDecoder().decode(Resp.self, from: data),
                  let members = r.elements?.first?.members else { continue }
            let coords = members.filter { $0.type == "way" }.flatMap { $0.geometry ?? [] }
                .map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
            if coords.count >= 3 { return [MKPolygon(coordinates: coords, count: coords.count)] }
        }
        return nil
    }
}
