import Foundation
import UIKit
import CoreLocation
import UserNotifications

/// A house offered to the canvasser. `on` = will be marked when they accept.
struct Candidate: Codable, Equatable, Identifiable {
    var lat: Double
    var lng: Double
    var num: String
    var street: String
    var addr: String
    var dist: Int
    var key: String
    var on: Bool
    var id: String { key }
    var ll: LatLng { LatLng(lat: lat, lng: lng) }
}

/// Street sweep: while clocked in, GPS builds a walking trail; every ~120 m the new stretch is
/// looked up (HouseFinder) and the houses passed become candidates the canvasser can mark as
/// door hangers in one tap. A port of app.html's "Street sweep" section, plus the old
/// wrapper's background tracking and walking reminder.
@MainActor @Observable
final class SweepTracker: NSObject, CLLocationManagerDelegate {
    enum GPS { case off, on, warn }

    private(set) var gps: GPS = .off
    private(set) var trail: [TrailPoint] = []
    /// Insertion order, like the web's object keys.
    private(set) var candidates: [Candidate] = []
    /// Bumped whenever the trail or candidates change, so the map redraws.
    private(set) var version = 0
    private(set) var isOn = false
    var toast: ((String) -> Void)?

    let uid: String
    private let pins: PinStore
    private var start: Int64 = 0
    private var seen = Set<String>()
    private var seg: [TrailPoint] = []
    private var segDist = 0.0
    private var segStart: Int64 = 0
    private var queue: [[TrailPoint]] = []
    private var busy = false
    /// Live "walked up to a house" check: one lookup at a time; the newest step waits its turn.
    private var nearBusy = false
    /// Recent fixes (about the last minute, walking or not) for the average-speed check.
    private var recent: [TrailPoint] = []
    private var lastDrivingAt: Int64 = .min
    private var lastWasDriving = false
    /// Consecutive fixes that each moved faster than walking pace.
    private var fastSteps = 0
    private var nearNext: [LatLng]?
    private var retryTimer: Timer?
    private var saveTask: Task<Void, Never>?

    private let manager = CLLocationManager()
    private var backgroundSession: CLBackgroundActivitySession?

    // Background walking reminder (from the old ios/ LocationBridge).
    private var bgDistance = 0.0
    private var lastBg: CLLocation?
    private var lastNotifyAt = Date.distantPast
    private static let notifyEveryMeters = 250.0
    private static let notifyMinInterval: TimeInterval = 300

    init(uid: String, pins: PinStore) {
        self.uid = uid
        self.pins = pins
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willResignActive),
                                               name: UIApplication.willResignActiveNotification, object: nil)
    }

    private var savedKey: String { "knoxTrail_\(uid)" }

    // MARK: Start / stop

    func start(clockIn: Int64) {
        guard !isOn else { return }
        isOn = true
        recent = []; lastDrivingAt = .min; lastWasDriving = false; fastSteps = 0
        start = clockIn
        // Pick the trail back up if the app was closed mid-shift.
        trail = []; seen = []; candidates = []
        if let data = UserDefaults.standard.data(forKey: savedKey),
           let saved = try? JSONDecoder().decode(Saved.self, from: data), saved.start == clockIn {
            trail = saved.pts.compactMap { $0.count >= 3 ? TrailPoint(lat: $0[0], lng: $0[1], t: Int64($0[2])) : nil }
            seen = Set(saved.seen)
            for c in saved.cands { addCandidate(House(lat: c.lat, lng: c.lng, num: c.num, street: c.street, addr: c.addr, dist: c.dist), on: c.on, restoring: true) }
        }
        seg = []; segDist = 0; segStart = 0
        version &+= 1

        gps = .on
        manager.allowsBackgroundLocationUpdates = true   // needs UIBackgroundModes = location
        manager.showsBackgroundLocationIndicator = true
        backgroundSession = CLBackgroundActivitySession()
        if checkAuthorization() { manager.startUpdatingLocation() }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Flush a stretch that's been sitting (stopped to talk at a door) and retry failed lookups.
                if self.seg.count > 1 && self.segDist >= 40 && nowMs() - self.segStart >= SWEEP.lookupMinMs { self.flushSeg() }
                self.processQueue()
            }
        }
    }

    /// `keepSaved`: signing out mid-shift (keep the trail on this device for next time).
    /// Otherwise clocking out: look up the last stretch so it can still be offered, then forget the trail.
    func stop(keepSaved: Bool) {
        isOn = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        backgroundSession?.invalidate()
        backgroundSession = nil
        retryTimer?.invalidate()
        retryTimer = nil
        gps = .off
        if keepSaved {
            saveTask?.cancel()
            candidates = []; queue = []; trail = []; seg = []; segDist = 0
        } else {
            if seg.count > 1 { queue.append(seg); processQueue() }
            seg = []; segDist = 0; trail = []
            UserDefaults.standard.removeObject(forKey: savedKey)
        }
        version &+= 1
    }

    // MARK: Location

    @discardableResult
    private func checkAuthorization() -> Bool {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization() // updates start in locationManagerDidChangeAuthorization
            return false
        case .denied, .restricted:
            reportDenied()
            return false
        default:
            if manager.accuracyAuthorization == .reducedAccuracy {
                toast?("Turn on Precise Location for KnoxCanvas in Settings so houses can be matched.")
            }
            return true
        }
    }

    private func reportDenied() {
        gps = .warn
        toast?("Location is off for KnoxCanvas. Turn it on in Settings \u{2192} KnoxCanvas \u{2192} Location (While Using the App).")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            guard isOn else { return }
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                gps = .on
                manager.startUpdatingLocation()
            case .denied, .restricted:
                reportDenied()
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            if (error as? CLError)?.code == .denied, isOn { reportDenied() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            let background = UIApplication.shared.applicationState != .active
            for loc in locations where loc.horizontalAccuracy >= 0 {
                addPoint(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude, acc: loc.horizontalAccuracy, speed: loc.speed,
                         t: Int64((loc.timestamp.timeIntervalSince1970 * 1000).rounded()))
                if background { noteBackgroundWalking(loc) }
            }
        }
    }

    /// app.html's sweepAddPoint.
    /// `speed` is the iPhone's own GPS speed in m/s (negative when unknown).
    func addPoint(lat: Double, lng: Double, acc: Double, speed: Double = -1, t: Int64) {
        guard isOn, lat.isFinite, lng.isFinite, acc <= SWEEP.maxAcc else { return }
        if gps != .on { gps = .on }
        let last = trail.last
        if let last, SweepGeo.dist(last.lat, last.lng, lat, lng) < SWEEP.minStep { return }
        let pt = TrailPoint(lat: lat, lng: lng, t: t)
        let driving = isDriving(pt, last: last, speed: speed)
        trail.append(pt)
        if driving {
            // In a car: close out the walked stretch; houses along the road don't count. The
            // quick step(s) just before this were the car pulling away, not walking.
            if fastSteps > 1 { seg.removeLast(min(fastSteps - 1, seg.count)) }
            if !seg.isEmpty { flushSeg() }
            seg = []; segDist = 0; segStart = 0
            lastWasDriving = true
        } else {
            if seg.isEmpty {
                // Back on foot: don't stitch the drive onto the new walked stretch.
                seg = (lastWasDriving ? nil : last).map { [$0] } ?? []; segDist = 0; segStart = pt.t
            }
            lastWasDriving = false
            if let prev = seg.last { segDist += SweepGeo.dist(prev.lat, prev.lng, pt.lat, pt.lng) }
            seg.append(pt)
        }
        version &+= 1
        save(now: false)
        // The step just walked (never the drive before it). A lone first fix waits for the
        // next one: until then there's no way to tell walking from driving.
        // A single quick step is held back too, until the next fix shows walking or driving.
        if !driving, fastSteps == 0, seg.count >= 2 { checkNear([seg[seg.count - 2].ll, pt.ll]) }
        if segDist >= SWEEP.lookupEvery || (segDist >= 40 && pt.t - segStart >= SWEEP.lookupMinMs) { flushSeg() }
    }

    /// Driving if the GPS speed, or the average over the last 10+ seconds, is faster than a
    /// walk, or if the walker was driving within the last 30 seconds (stopped at a light,
    /// just parked). Car GPS fixes come every second or so, only 10\u{2013}15 m apart, so the
    /// gap between two fixes alone can't tell a car from a walk.
    private func isDriving(_ pt: TrailPoint, last: TrailPoint?, speed: Double) -> Bool {
        recent.append(pt)
        recent.removeAll { pt.t - $0.t > 60_000 }
        var fast = speed > SWEEP.maxWalkSpeed
        if !fast, let past = recent.last(where: { pt.t - $0.t >= SWEEP.speedWindowMs }) {
            let dt = Double(pt.t - past.t) / 1000
            fast = dt > 0 && SweepGeo.dist(past.ll, pt.ll) / dt > SWEEP.maxWalkSpeed
        }
        if let last {
            let d = SweepGeo.dist(last.ll, pt.ll), dt = Double(pt.t - last.t) / 1000
            let stepFast = dt > 0 && d / dt > SWEEP.maxWalkSpeed
            fastSteps = stepFast ? fastSteps + 1 : 0
            // One quick step can be a GPS jump; two in a row (or one long one) is a car.
            if stepFast && (d > 25 || fastSteps >= 2) { fast = true }
        }
        if fast { lastDrivingAt = pt.t }
        return fast || (lastDrivingAt != .min && pt.t - lastDrivingAt < SWEEP.driveCooldownMs)
    }

    private func flushSeg() {
        let s = seg
        seg = []; segDist = 0; segStart = 0
        guard s.count >= 2, SweepGeo.lineLength(s.map(\.ll)) >= 15 else { return }
        queue.append(s)
        processQueue()
    }

    private func processQueue() {
        guard !busy, !queue.isEmpty else { return }
        busy = true
        Task {
            var added = 0
            while let s = queue.first {
                let houses: [House]
                do { houses = try await HouseFinder.housesAlong(s.map(\.ll)) }
                catch { print("sweep lookup:", error); break } // keep it queued and retry later
                queue.removeFirst()
                for h in houses where addCandidate(h, on: true, restoring: false) { added += 1 }
            }
            busy = false
            if added > 0 {
                version &+= 1
                save(now: true)
                if UIApplication.shared.applicationState == .active {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
    }

    /// Lights up houses as soon as the walker comes within `SWEEP.doorRadius` of them, using
    /// the address tiles. The 120 m stretch lookups still run afterwards and catch anything
    /// missed (no signal, tile not loaded yet) and cover areas without tiles.
    private func checkNear(_ step: [LatLng]) {
        guard !nearBusy else { nearNext = step; return }
        nearBusy = true
        Task {
            let houses = await HouseFinder.tileHousesNear(step) ?? []
            var added = 0
            for h in houses where addCandidate(h, on: true, restoring: false) { added += 1 }
            if added > 0 {
                version &+= 1
                save(now: true)
                if UIApplication.shared.applicationState == .active {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
            nearBusy = false
            if let next = nearNext { nearNext = nil; checkNear(next) }
        }
    }

    // MARK: Candidates

    static func key(_ lat: Double, _ lng: Double) -> String { String(format: "%.5f,%.5f", lat, lng) }

    @discardableResult
    private func addCandidate(_ h: House, on: Bool, restoring: Bool) -> Bool {
        let key = Self.key(h.lat, h.lng)
        if seen.contains(key) || candidates.contains(where: { $0.key == key }) { return false }
        if !restoring && pins.hasPin(near: h.lat, h.lng, within: SWEEP.dupRadius) { seen.insert(key); return false } // already pinned
        // Same house tagged twice (node + building): keep one.
        if candidates.contains(where: { (!h.addr.isEmpty && $0.addr == h.addr) || SweepGeo.dist($0.ll, h.ll) < 6 }) { return false }
        candidates.append(Candidate(lat: h.lat, lng: h.lng, num: h.num, street: h.street, addr: h.addr, dist: h.dist, key: key, on: on))
        return true
    }

    func toggle(_ key: String) {
        guard let i = candidates.firstIndex(where: { $0.key == key }) else { return }
        candidates[i].on.toggle()
        version &+= 1
        save(now: false)
    }

    func setAll(_ on: Bool) {
        for i in candidates.indices { candidates[i].on = on }
        version &+= 1
    }

    /// Marks the selected houses as hangers. Everything shown (marked or left out) is done:
    /// those houses aren't offered again this shift.
    func accept() {
        let chosen = candidates.filter(\.on)
        let n = pins.createSweepPins(chosen)
        finish()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        toast?(n > 0 ? "Marked \(n) door hanger\(n == 1 ? "" : "s")" : "Skipped")
    }

    func skip() { finish() }

    private func finish() {
        for c in candidates { seen.insert(c.key) }
        candidates = []
        version &+= 1
        save(now: true)
    }

    // MARK: Banner text

    var title: String {
        let n = candidates.count
        return "\u{1F3E0} \(n) house\(n == 1 ? "" : "s") visited \u{00B7} \(Self.streetsSummary(candidates))"
    }

    var subtitle: String {
        let on = candidates.filter(\.on).count
        return on == candidates.count ? "Tap an orange ring to leave a house out."
            : "\(candidates.count - on) left out. Tap a ring to change it."
    }

    static func streetsSummary(_ list: [Candidate]) -> String {
        var count: [String: Int] = [:]
        var order: [String] = []
        for c in list {
            let s = c.street.isEmpty ? "Nearby" : c.street
            if count[s] == nil { order.append(s) }
            count[s, default: 0] += 1
        }
        let names = order.enumerated().sorted { (count[$0.element]!, -$0.offset) > (count[$1.element]!, -$1.offset) }.map(\.element)
        return names.count <= 2 ? names.joined(separator: " & ") : "\(names[0]), \(names[1]) +\(names.count - 2) more"
    }

    /// Grouped by street, then house number, like the web's review list.
    var sortedCandidates: [Candidate] {
        candidates.sorted {
            let a = $0.street, b = $1.street
            if a != b { return a.localizedCompare(b) == .orderedAscending }
            return (Int($0.num.prefix { $0.isNumber }) ?? 0) < (Int($1.num.prefix { $0.isNumber }) ?? 0)
        }
    }

    // MARK: Shift summary

    /// `trail` as "lat,lng,secondsSinceClockIn;..." (Firestore can't store nested arrays) and `trailMeters`.
    func shiftSummary(since: Int64) -> (trail: String, meters: Int) {
        let pts = trail.count > 4000 ? SweepGeo.thin(trail, 4000) : trail
        let s = pts.map { String(format: "%.5f,%.5f,%lld", $0.lat, $0.lng, Int64((Double($0.t - since) / 1000).rounded())) }
            .joined(separator: ";")
        return (s, Int(SweepGeo.lineLength(trail.map(\.ll)).rounded()))
    }

    // MARK: Saving (survives the app being closed mid-shift)

    private struct Saved: Codable {
        var start: Int64
        var pts: [[Double]]
        var seen: [String]
        var cands: [Candidate]
    }

    private func save(now: Bool) {
        saveTask?.cancel()
        let write = { [weak self] in
            guard let self, self.start > 0, self.isOn || !self.candidates.isEmpty else { return }
            let saved = Saved(start: self.start,
                              pts: self.trail.suffix(5000).map { [($0.lat * 1e6).rounded() / 1e6, ($0.lng * 1e6).rounded() / 1e6, Double($0.t)] },
                              seen: Array(self.seen.suffix(3000)), cands: self.candidates)
            if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: self.savedKey) }
        }
        if now { write(); return }
        saveTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { write() }
        }
    }

    // MARK: Background reminder

    /// With the phone in a pocket the banner can't be seen, so every ~250 m of walking send a
    /// quiet notification reminding them to open the app and mark houses.
    private func noteBackgroundWalking(_ loc: CLLocation) {
        guard isOn, loc.horizontalAccuracy <= SWEEP.maxAcc else { return }
        if let last = lastBg {
            let d = loc.distance(from: last), dt = loc.timestamp.timeIntervalSince(last.timestamp)
            if dt > 0 && d / dt < SWEEP.maxWalkSpeed { bgDistance += d } // walking only, not driving
        }
        lastBg = loc
        guard bgDistance >= Self.notifyEveryMeters, Date().timeIntervalSince(lastNotifyAt) >= Self.notifyMinInterval else { return }
        lastNotifyAt = Date()
        let feet = Int(bgDistance * 3.281)
        bgDistance = 0
        let content = UNMutableNotificationContent()
        let n = candidates.count
        content.title = "Mark the houses you passed"
        content.body = n > 0
            ? "\(n) house\(n == 1 ? "" : "s") waiting. Open KnoxCanvas to mark them as door hangers."
            : "You've walked about \(feet) ft. Open KnoxCanvas to drop door hanger pins on that street."
        content.sound = nil
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "knox-walk", content: content, trigger: nil))
    }

    @objc private func didBecomeActive() {
        bgDistance = 0
        lastBg = nil
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["knox-walk"])
        processQueue()
    }

    @objc private func willResignActive() { save(now: true) }
}
