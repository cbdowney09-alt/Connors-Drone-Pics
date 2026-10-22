import Foundation
import CoreLocation

/// Downloadable house data, one file per state, hosted as GitHub release assets (free, built by
/// tools/address-tiles/build.py + pack.py and published with tools/address-tiles/publish.sh).
/// The owner picks the company's states (`companies/{id}.states`); every phone on the team
/// downloads them on sign-in. Anyone can add or remove states under Account → House data.
@MainActor @Observable
final class StatePacks {
    static let shared = StatePacks()

    /// Where the release lives. `manifest.json` lists every state; `XX.knxa` is each state.
    /// The `knoxPacksBase` default overrides it for testing against a local copy.
    static let releaseBase = UserDefaults.standard.string(forKey: "knoxPacksBase").flatMap(URL.init(string:))
        ?? URL(string: "https://github.com/cbdowney09-alt/Connors-Drone-Pics/releases/download/address-data-v1/")!

    /// Application Support, not Caches: iOS clears caches when space is low, and these must
    /// survive for offline walks. Excluded from iCloud backup since they can be downloaded again.
    nonisolated static let directory: URL = {
        var d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("addr-packs", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? d.setResourceValues(values)
        return d
    }()

    struct Info: Codable, Identifiable, Equatable {
        let code: String
        let name: String
        let bytes: Int
        let houses: Int
        let version: String
        var id: String { code }
    }
    private struct Manifest: Codable { let version: String; let source: String; let states: [Info] }

    private(set) var available: [Info] = []
    /// Installed state -> data version.
    private(set) var installed: [String: String] = [:]
    /// State -> 0...1 while downloading.
    private(set) var progress: [String: Double] = [:]
    private(set) var failed: Set<String> = []
    private(set) var manifestError = false

    private let installedKey = "knoxStatePacks"
    private var manifestFile: URL { Self.directory.appendingPathComponent("manifest.json") }
    private var queue: [String] = []
    private var running = false

    private init() {
        installed = (UserDefaults.standard.dictionary(forKey: installedKey) as? [String: String]) ?? [:]
        // Drop entries whose file is gone (e.g. the app's data was cleared).
        installed = installed.filter { FileManager.default.fileExists(atPath: file($0.key).path) }
        if let data = try? Data(contentsOf: manifestFile), let m = try? JSONDecoder().decode(Manifest.self, from: data) {
            available = m.states
        }
    }

    func file(_ code: String) -> URL { Self.directory.appendingPathComponent("\(code).knxa") }

    func info(_ code: String) -> Info? { available.first { $0.code == code } }
    func name(_ code: String) -> String { info(code)?.name ?? StatePacks.names[code] ?? code }
    var isDownloading: Bool { !progress.isEmpty }
    func hasUpdate(_ code: String) -> Bool {
        guard let have = installed[code], let latest = info(code)?.version else { return false }
        return have != latest
    }

    /// Fetches the list of states (sizes, versions). Uses the saved copy when offline.
    func loadManifest() async {
        var req = URLRequest(url: Self.releaseBase.appendingPathComponent("manifest.json"))
        req.timeoutInterval = 15
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if let (data, resp) = try? await URLSession.shared.data(for: req),
           (resp as? HTTPURLResponse)?.statusCode == 200,
           let m = try? JSONDecoder().decode(Manifest.self, from: data) {
            try? data.write(to: manifestFile)
            available = m.states
            manifestError = false
        } else if available.isEmpty {
            manifestError = true
        }
    }

    /// Downloads any of these states that aren't on the phone yet (the company's states).
    func ensure(_ codes: [String]) {
        for c in codes where installed[c] == nil && !queue.contains(c) && progress[c] == nil { queue.append(c) }
        run()
    }

    func download(_ code: String) {
        failed.remove(code)
        if !queue.contains(code) && progress[code] == nil { queue.append(code) }
        run()
    }

    func remove(_ code: String) {
        try? FileManager.default.removeItem(at: file(code))
        installed[code] = nil
        save()
        Task { await AddressTiles.shared.reloadPacks() }
    }

    func bytesOnDisk(_ code: String) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: file(code).path))?[.size] as? NSNumber)?.intValue ?? 0
    }

    private func save() { UserDefaults.standard.set(installed, forKey: installedKey) }

    private func run() {
        guard !running, !queue.isEmpty else { return }
        running = true
        Task {
            if available.isEmpty { await loadManifest() }
            while !queue.isEmpty {
                let code = queue.removeFirst()
                await fetch(code)
            }
            running = false
        }
    }

    private func fetch(_ code: String) async {
        progress[code] = 0
        defer { progress[code] = nil }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(code)-\(UUID().uuidString).knxa")
        do {
            try await Self.downloadFile(Self.releaseBase.appendingPathComponent("\(code).knxa"), to: tmp) { [weak self] p in
                Task { @MainActor in if self?.progress[code] != nil { self?.progress[code] = p } }
            }
            guard AddressTiles.isValidPack(tmp) else { throw URLError(.cannotDecodeContentData) }
            let dest = file(code)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            installed[code] = info(code)?.version ?? "1"
            save()
            failed.remove(code)
            await AddressTiles.shared.reloadPacks()
        } catch {
            print("state pack \(code):", error)
            try? FileManager.default.removeItem(at: tmp)
            failed.insert(code)
        }
    }

    /// A download task with progress (GitHub redirects release assets; URLSession follows).
    private nonisolated static func downloadFile(_ url: URL, to dest: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            var observation: NSKeyValueObservation?
            let task = URLSession.shared.downloadTask(with: url) { tmp, resp, error in
                observation?.invalidate()
                if let error { c.resume(throwing: error); return }
                guard let tmp, (resp as? HTTPURLResponse)?.statusCode == 200 else {
                    c.resume(throwing: URLError(.badServerResponse)); return
                }
                do {
                    try FileManager.default.moveItem(at: tmp, to: dest)
                    c.resume()
                } catch { c.resume(throwing: error) }
            }
            observation = task.progress.observe(\.fractionCompleted) { p, _ in progress(p.fractionCompleted) }
            task.resume()
        }
    }

    /// The state the phone is in right now ("TN"), from its last known location.
    static func currentState() async -> String? {
        guard let loc = CLLocationManager().location else { return nil }
        let marks = try? await CLGeocoder().reverseGeocodeLocation(loc)
        guard let code = marks?.first?.administrativeArea, names[code] != nil else { return nil }
        return code
    }

    static let names: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California", "CO": "Colorado",
        "CT": "Connecticut", "DE": "Delaware", "DC": "District of Columbia", "FL": "Florida", "GA": "Georgia",
        "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa", "KS": "Kansas",
        "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland", "MA": "Massachusetts",
        "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi", "MO": "Missouri", "MT": "Montana",
        "NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico",
        "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma",
        "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota",
        "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington",
        "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming", "PR": "Puerto Rico",
    ]
}
