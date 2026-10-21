import Foundation

/// One house from our address tiles (Overture Maps / National Address Database), built by
/// tools/address-tiles/build.py and served from the website at /addr/v1/.
struct TileAddress {
    let lat: Double
    let lng: Double
    let number: String
    let street: String
    /// "Knoxville 37909"
    let cityZip: String
    let state: String

    var ll: LatLng { LatLng(lat: lat, lng: lng) }

    /// "6802 Sheffield Drive, Knoxville, TN 37909", the same shape as geocoded pin addresses.
    var addr: String {
        let parts = cityZip.split(separator: " ")
        let zip = parts.last.map(String.init).flatMap { $0.allSatisfy(\.isNumber) ? $0 : nil }
        let city = (zip == nil ? parts : parts.dropLast()).joined(separator: " ")
        let tail = [state, zip].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return ["\(number) \(street)", city, tail].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// Loads address tiles on demand and keeps them on the phone (they rarely change), so the
/// route optimizer and the street sweep don't depend on the public Overpass servers.
actor AddressTiles {
    static let shared = AddressTiles()
    /// The `knoxAddrBase` default overrides it for testing against a local copy.
    static let base = UserDefaults.standard.string(forKey: "knoxAddrBase").flatMap(URL.init(string:))
        ?? URL(string: "https://connorsdronepics.com/addr/v1/")!

    private struct Index: Decodable { let v: Int; let tileDeg: Double; let tiles: [String] }
    private struct Tile: Decodable {
        let st: String
        let lat0: Double
        let lng0: Double
        let s: [String]
        let c: [String]
        let a: [Row]
        struct Row: Decodable {
            let dLat: Int, dLng: Int, number: String, street: Int, city: Int
            init(from d: Decoder) throws {
                var c = try d.unkeyedContainer()
                dLat = try c.decode(Int.self); dLng = try c.decode(Int.self)
                number = try c.decode(String.self)
                street = try c.decode(Int.self); city = try c.decode(Int.self)
            }
        }
    }

    private var index: (deg: Double, tiles: Set<String>)?
    private var indexLoadedAt: Date?
    private var memory: [String: [TileAddress]] = [:]
    private let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("addr-v1")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// Houses inside the box, or nil when this area has no tiles (or the tiles couldn't be
    /// reached and aren't cached), so the caller can fall back to Overpass.
    func addresses(minLat: Double, minLng: Double, maxLat: Double, maxLng: Double) async -> [TileAddress]? {
        guard let idx = await loadIndex() else { return nil }
        let d = idx.deg
        var keys: [String] = []
        for ty in Int(floor(minLat / d))...Int(floor(maxLat / d)) {
            for tx in Int(floor(minLng / d))...Int(floor(maxLng / d)) { keys.append("\(ty)/\(tx)") }
        }
        guard keys.count <= 16 else { return nil } // a huge zone; not worth hundreds of tiles
        let covered = keys.filter { idx.tiles.contains($0) }
        guard !covered.isEmpty else { return nil }
        var out: [TileAddress] = []
        for k in covered {
            guard let houses = await tile(k) else { return nil }
            out += houses.filter { $0.lat >= minLat && $0.lat <= maxLat && $0.lng >= minLng && $0.lng <= maxLng }
        }
        return out
    }

    private func loadIndex() async -> (deg: Double, tiles: Set<String>)? {
        let file = dir.appendingPathComponent("index.json")
        // Refresh about weekly; use the saved copy when offline.
        if let index, let at = indexLoadedAt, Date().timeIntervalSince(at) < 7 * 86_400 { return index }
        if let data = await fetch(Self.base.appendingPathComponent("index.json"), timeout: 10),
           let i = try? JSONDecoder().decode(Index.self, from: data) {
            try? data.write(to: file)
            index = (i.tileDeg, Set(i.tiles))
            indexLoadedAt = Date()
        } else if index == nil, let data = try? Data(contentsOf: file),
                  let i = try? JSONDecoder().decode(Index.self, from: data) {
            index = (i.tileDeg, Set(i.tiles))
        }
        return index
    }

    private func tile(_ key: String) async -> [TileAddress]? {
        if let m = memory[key] { return m }
        let file = dir.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_") + ".json")
        var data = try? Data(contentsOf: file)
        if data == nil, let fresh = await fetch(Self.base.appendingPathComponent(key + ".json"), timeout: 15) {
            try? fresh.write(to: file)
            data = fresh
        }
        guard let data, let t = try? JSONDecoder().decode(Tile.self, from: data) else { return nil }
        let houses = t.a.compactMap { r -> TileAddress? in
            guard r.street < t.s.count, r.city < t.c.count else { return nil }
            return TileAddress(lat: t.lat0 + Double(r.dLat) / 1e5, lng: t.lng0 + Double(r.dLng) / 1e5,
                               number: r.number, street: t.s[r.street], cityZip: t.c[r.city], state: t.st)
        }
        if memory.count > 24 { memory.removeAll() }
        memory[key] = houses
        return houses
    }

    private func fetch(_ url: URL, timeout: TimeInterval) async -> Data? {
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
