import Foundation

/// A house the canvasser walked past.
struct House: Codable, Equatable {
    var lat: Double
    var lng: Double
    var num: String
    var street: String
    var addr: String
    var dist: Int

    var ll: LatLng { LatLng(lat: lat, lng: lng) }
}

/// Finds addressed houses along a walked stretch: OSM Overpass first (houses whose street
/// matches a street actually walked), then Google reverse geocoding through the Worker.
/// Same logic as app.html's findHousesAlong / geocodeAlong.
enum HouseFinder {
    static let overpass = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
        "https://overpass.openstreetmap.ru/api/interpreter",
    ]

    struct Offline: Error {}

    /// Throws `Offline` when nothing could be reached, so the stretch stays queued for a retry.
    static func housesAlong(_ seg: [LatLng]) async throws -> [House] {
        let line = SweepGeo.thin(seg, 40)
        let coords = line.map { String(format: "%.6f,%.6f", $0.lat, $0.lng) }.joined(separator: ",")
        let r = Int(SWEEP.roadRadius), h = Int(SWEEP.houseRadius)
        let q = "[out:json][timeout:20];way(around:\(r),\(coords))[\"highway\"][\"name\"];out tags;"
            + "(node(around:\(h),\(coords))[\"addr:housenumber\"];way(around:\(h),\(coords))[\"addr:housenumber\"];);out center tags;"
        let elements = await overpassElements(q)

        let houses = elements.map { match($0, line: line) } ?? []

        // No OSM addresses here (common outside big cities): ask Google along the trail.
        if houses.isEmpty && SweepGeo.lineLength(seg) >= 50 && (elements == nil || elements!.contains { $0.tags["highway"] != nil }) {
            let fb = await geocodeAlong(line)
            if fb == nil && elements == nil { throw Offline() }
            return fb ?? []
        }
        return elements == nil ? [] : houses
    }

    /// Keeps addressed houses near the line whose street is one actually walked.
    static func match(_ elements: [Element], line: [LatLng]) -> [House] {
        var roads = Set<String>()
        for el in elements {
            if el.tags["highway"] != nil, let name = el.tags["name"] { roads.insert(SweepGeo.normStreet(name)) }
        }
        var houses: [House] = []
        for el in elements {
            let t = el.tags
            guard let num = t["addr:housenumber"], let lat = el.lat, let lng = el.lon else { continue }
            let street = t["addr:street"] ?? ""
            let d = SweepGeo.distToLine(LatLng(lat: lat, lng: lng), line)
            if d > SWEEP.houseRadius { continue }
            if !street.isEmpty {
                // Backs onto a different street.
                if !roads.isEmpty && !roads.contains(SweepGeo.normStreet(street)) { continue }
            } else if d > SWEEP.noStreetRadius { continue }
            let city = t["addr:city"]
            let stateZip = [t["addr:state"] ?? (city != nil ? "TN" : nil), t["addr:postcode"]]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            let cityLine = [city, stateZip.isEmpty ? nil : stateZip].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            let first = "\(num) \(street)".trimmingCharacters(in: .whitespaces)
            let addr = [first, cityLine].filter { !$0.isEmpty }.joined(separator: ", ")
            houses.append(House(lat: lat, lng: lng, num: num, street: street, addr: addr, dist: Int(d.rounded())))
        }
        return houses
    }

    // MARK: Overpass

    struct Element: Decodable {
        struct Center: Decodable { let lat: Double; let lon: Double }
        let lat: Double?
        let lon: Double?
        let tags: [String: String]

        enum CodingKeys: String, CodingKey { case lat, lon, center, tags }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let center = try c.decodeIfPresent(Center.self, forKey: .center)
            lat = try c.decodeIfPresent(Double.self, forKey: .lat) ?? center?.lat
            lon = try c.decodeIfPresent(Double.self, forKey: .lon) ?? center?.lon
            tags = (try? c.decodeIfPresent([String: String].self, forKey: .tags)) ?? [:]
        }
    }

    private struct OverpassResponse: Decodable { let elements: [Element]? }

    /// Tries each endpoint in turn. Nil if none answered. The web uses 15 s, but a busy
    /// overpass-api.de often needs longer, and this runs off the main thread anyway.
    static func overpassElements(_ query: String, timeout: TimeInterval = 30) async -> [Element]? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        let body = "data=" + (query.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        for ep in overpass {
            var req = URLRequest(url: URL(string: ep)!)
            req.httpMethod = "POST"
            req.timeoutInterval = timeout
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.setValue("KnoxCanvas/2.0 (iOS door-to-door canvassing app)", forHTTPHeaderField: "User-Agent")
            req.httpBody = Data(body.utf8)
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let r = try? JSONDecoder().decode(OverpassResponse.self, from: data),
                  let els = r.elements else { continue }
            return els
        }
        return nil
    }

    // MARK: Google fallback

    private struct GeoResponse: Decodable {
        struct Result: Decodable {
            struct Component: Decodable { let short_name: String?; let types: [String]? }
            struct Geometry: Decodable {
                struct Loc: Decodable { let lat: Double; let lng: Double }
                let location: Loc?
                let location_type: String?
            }
            let formatted_address: String?
            let geometry: Geometry?
            let types: [String]?
            let address_components: [Component]?
        }
        let status: String?
        let results: [Result]?
    }

    /// Up to 5 samples 40 m apart; ROOFTOP street addresses only. Nil if the Worker never answered.
    static func geocodeAlong(_ line: [LatLng]) async -> [House]? {
        var found: [String: House] = [:]
        var order: [String] = []
        var anyOk = false
        for s in SweepGeo.samplesAlong(line, every: 40, maxCount: 5) {
            var comps = URLComponents(url: AppConfig.geocodeWorker, resolvingAgainstBaseURL: false)!
            comps.queryItems = [.init(name: "lat", value: String(s.lat)), .init(name: "lng", value: String(s.lng))]
            var req = URLRequest(url: comps.url!)
            req.timeoutInterval = 12
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let d = try? JSONDecoder().decode(GeoResponse.self, from: data),
                  // REQUEST_DENIED etc. is not an answer: leave the stretch queued for a retry.
                  d.status == "OK" || d.status == "ZERO_RESULTS" else { continue }
            anyOk = true
            for res in d.results ?? [] {
                guard res.geometry?.location_type == "ROOFTOP",
                      (res.types ?? []).contains(where: { $0 == "street_address" || $0 == "premise" }),
                      let loc = res.geometry?.location else { continue }
                let p = LatLng(lat: loc.lat, lng: loc.lng)
                let dd = SweepGeo.distToLine(p, line)
                if dd > SWEEP.houseRadius { continue }
                func comp(_ type: String) -> String {
                    res.address_components?.first { $0.types?.contains(type) ?? false }?.short_name ?? ""
                }
                var addr = res.formatted_address ?? ""
                if addr.hasSuffix(", USA") { addr.removeLast(5) }
                let num = comp("street_number")
                guard !num.isEmpty, !addr.isEmpty else { continue }
                if found[addr] == nil { order.append(addr) }
                found[addr] = House(lat: loc.lat, lng: loc.lng, num: num, street: comp("route"), addr: addr, dist: Int(dd.rounded()))
            }
        }
        return anyOk ? order.compactMap { found[$0] } : nil
    }
}
