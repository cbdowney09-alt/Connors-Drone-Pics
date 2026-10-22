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

/// House addresses for the route optimizer and the street sweep, so they don't depend on the
/// public Overpass servers. Each state is a downloaded pack (`StatePacks`, one .knxa file per
/// state made by tools/address-tiles/pack.py) and works with no signal. Areas with no pack fall
/// back to the website's tiles (/addr/v1/, Tennessee and North Carolina), kept once fetched.
actor AddressTiles {
    static let shared = AddressTiles()
    /// The `knoxAddrBase` default overrides it for testing against a local copy.
    static let base = UserDefaults.standard.string(forKey: "knoxAddrBase").flatMap(URL.init(string:))
        ?? URL(string: "https://connorsdronepics.com/addr/v1/")!
    static let tileDeg = 0.05

    private struct Index: Decodable { let v: Int; let tileDeg: Double; let tiles: [String] }
    private struct Tile: Decodable {
        let st: String
        /// State per city, on website tiles that straddle a state line.
        let cs: [String]?
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

    /// One state's pack: tile key -> (offset, length) of its compressed JSON.
    private struct Pack { let data: Data; let tiles: [String: (Int, Int)] }

    private var index: (deg: Double, tiles: Set<String>)?
    private var indexLoadedAt: Date?
    private var indexFailedAt: Date?
    private var packs: [String: Pack]?
    private var memory: [String: [TileAddress]] = [:]
    private let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("addr-v1")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// Call after a state is downloaded or removed.
    func reloadPacks() {
        packs = nil
        memory.removeAll()
    }

    /// Houses inside the box, or nil when this area has no data (or the website tiles couldn't
    /// be reached and aren't cached), so the caller can fall back to Overpass.
    func addresses(minLat: Double, minLng: Double, maxLat: Double, maxLng: Double) async -> [TileAddress]? {
        let packs = loadPacks()
        let d = Self.tileDeg
        var keys: [String] = []
        for ty in Int(floor(minLat / d))...Int(floor(maxLat / d)) {
            for tx in Int(floor(minLng / d))...Int(floor(maxLng / d)) { keys.append("\(ty)/\(tx)") }
        }
        guard keys.count <= 16 else { return nil } // a huge zone; not worth hundreds of tiles
        let inPacks = Set(keys.filter { k in packs.values.contains { $0.tiles[k] != nil } })
        var web: [String] = []
        // Only ask the website about tiles no downloaded state covers.
        if inPacks.count < keys.count, let idx = await loadIndex() {
            web = keys.filter { !inPacks.contains($0) && idx.tiles.contains($0) }
        }
        guard !inPacks.isEmpty || !web.isEmpty else { return nil }
        var out: [TileAddress] = []
        for k in keys where inPacks.contains(k) || web.contains(k) {
            guard let houses = await tile(k, packs: packs) else { return nil }
            out += houses.filter { $0.lat >= minLat && $0.lat <= maxLat && $0.lng >= minLng && $0.lng <= maxLng }
        }
        return out
    }

    /// Reads each downloaded pack's table once; tile bodies are read on demand.
    private func loadPacks() -> [String: Pack] {
        if let packs { return packs }
        var out: [String: Pack] = [:]
        let files = (try? FileManager.default.contentsOfDirectory(at: StatePacks.directory, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.pathExtension == "knxa" {
            if let p = Self.readPack(url) { out[url.deletingPathExtension().lastPathComponent] = p }
        }
        packs = out
        return out
    }

    private static func readPack(_ url: URL) -> Pack? {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped), data.count > 16,
              data.prefix(4) == Data("KNXA".utf8) else { return nil }
        func u32(_ o: Int) -> Int { Int(data[o..<o + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian) }
        func i32(_ o: Int) -> Int { Int(data[o..<o + 4].withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }.littleEndian) }
        func u64(_ o: Int) -> Int { Int(data[o..<o + 8].withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.littleEndian) }
        let count = u32(8), metaLen = u32(12)
        guard data.count >= 16 + metaLen + count * 20 else { return nil }
        var tiles: [String: (Int, Int)] = [:]
        var o = 16 + metaLen
        for _ in 0..<count {
            let off = u64(o + 8), len = u32(o + 16)
            guard off + len <= data.count else { return nil } // a cut-off download
            tiles["\(i32(o))/\(i32(o + 4))"] = (off, len)
            o += 20
        }
        return Pack(data: data, tiles: tiles)
    }

    /// Valid pack file? Used to check a download before keeping it.
    static func isValidPack(_ url: URL) -> Bool { readPack(url) != nil }

    private func loadIndex() async -> (deg: Double, tiles: Set<String>)? {
        let file = dir.appendingPathComponent("index.json")
        // Refresh about weekly; use the saved copy when offline. After a failed fetch, wait
        // before asking again so walks with no signal don't keep stalling on it.
        if let index, let at = indexLoadedAt, Date().timeIntervalSince(at) < 7 * 86_400 { return index }
        if let failed = indexFailedAt, Date().timeIntervalSince(failed) < 600 { return index }
        if let data = await fetch(Self.base.appendingPathComponent("index.json"), timeout: 10),
           let i = try? JSONDecoder().decode(Index.self, from: data) {
            try? data.write(to: file)
            index = (i.tileDeg, Set(i.tiles))
            indexLoadedAt = Date()
        } else if index == nil, let data = try? Data(contentsOf: file),
                  let i = try? JSONDecoder().decode(Index.self, from: data) {
            index = (i.tileDeg, Set(i.tiles))
            indexFailedAt = Date()
        } else {
            indexFailedAt = Date()
        }
        return index
    }

    /// One tile's houses from every downloaded state that has it (tiles on a state line are in
    /// both states' packs), or else from the website.
    private func tile(_ key: String, packs: [String: Pack]) async -> [TileAddress]? {
        if let m = memory[key] { return m }
        var blobs: [Data] = []
        for p in packs.values {
            guard let (off, len) = p.tiles[key],
                  let raw = try? (p.data.subdata(in: off..<off + len) as NSData).decompressed(using: .zlib) as Data
            else { continue }
            blobs.append(raw)
        }
        if blobs.isEmpty {
            let file = dir.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_") + ".json")
            if let saved = try? Data(contentsOf: file) {
                blobs.append(saved)
            } else if let fresh = await fetch(Self.base.appendingPathComponent(key + ".json"), timeout: 15) {
                try? fresh.write(to: file)
                blobs.append(fresh)
            }
        }
        guard !blobs.isEmpty else { return nil }
        var houses: [TileAddress] = []
        for data in blobs {
            guard let t = try? JSONDecoder().decode(Tile.self, from: data) else { continue }
            houses += t.a.compactMap { r -> TileAddress? in
                guard r.street < t.s.count, r.city < t.c.count else { return nil }
                return TileAddress(lat: t.lat0 + Double(r.dLat) / 1e5, lng: t.lng0 + Double(r.dLng) / 1e5,
                                   number: r.number, street: t.s[r.street], cityZip: t.c[r.city],
                                   state: t.cs.flatMap { r.city < $0.count ? $0[r.city] : nil } ?? t.st)
            }
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
