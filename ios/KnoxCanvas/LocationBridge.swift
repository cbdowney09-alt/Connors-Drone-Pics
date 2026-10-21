import CoreLocation
import UIKit
import UserNotifications
import WebKit

/// Owns the one CLLocationManager in the app and feeds the web page.
///
/// Two jobs:
/// 1. Shift tracking: while the canvasser is clocked in, collect GPS points, including
///    with the screen locked or the app in the background (blue location pill). Points are
///    buffered (and saved to disk) and handed to `window.KnoxNative.onLocations` whenever
///    the page is visible, so the page can find the houses on the streets they walked.
/// 2. `navigator.geolocation` for the page (see BridgeScript), e.g. the "locate me" button.
final class LocationBridge: NSObject, CLLocationManagerDelegate {
    static let shared = LocationBridge()

    weak var webView: WKWebView?

    private let manager = CLLocationManager()
    private var tracking = false          // clocked-in shift tracking is on
    private var geoActive = false         // the page has a pending navigator.geolocation request
    private var pageReady = false         // page said startTracking since it last loaded
    private var flushing = false
    private var buffer: [[String: Double]] = []

    // Background walking reminder
    private var bgDistance: CLLocationDistance = 0
    private var lastBgLocation: CLLocation?
    private var lastNotifyAt = Date.distantPast
    private let notifyEveryMeters: CLLocationDistance = 250
    private let notifyMinInterval: TimeInterval = 300

    private let bufferKey = "knoxPendingLocations"
    private let trackingKey = "knoxTracking"
    private let maxBuffer = 20000

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        buffer = (UserDefaults.standard.array(forKey: bufferKey) as? [[String: Double]]) ?? []
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        // The app was closed mid-shift: keep collecting until the page catches up.
        if UserDefaults.standard.bool(forKey: trackingKey) { startTracking() }
    }

    // MARK: - Messages from the page

    /// Page is clocked in and ready to receive points.
    func pageStartedTracking() {
        pageReady = true
        if !tracking { startTracking() }
        flush()
    }

    /// Page clocked out.
    func pageStoppedTracking() {
        tracking = false
        UserDefaults.standard.set(false, forKey: trackingKey)
        buffer.removeAll()
        saveBuffer(force: true)
        manager.allowsBackgroundLocationUpdates = false
        if !geoActive { manager.stopUpdatingLocation() }
    }

    func geoStart() {
        geoActive = true
        guard checkAuthorization(forPage: true) else { return }
        manager.startUpdatingLocation()
        if let loc = manager.location, -loc.timestamp.timeIntervalSinceNow < 15 { deliverToGeo(loc) }
    }

    func geoStop() {
        geoActive = false
        if !tracking { manager.stopUpdatingLocation() }
    }

    /// The web view started loading a new page; wait for it to ask again before sending points.
    func pageWillLoad() {
        pageReady = false
        flushing = false
    }

    // MARK: - Tracking

    private func startTracking() {
        tracking = true
        UserDefaults.standard.set(true, forKey: trackingKey)
        manager.allowsBackgroundLocationUpdates = true      // needs UIBackgroundModes = location
        manager.showsBackgroundLocationIndicator = true
        if checkAuthorization(forPage: false) { manager.startUpdatingLocation() }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Returns true if we can start updates now. Asks for permission or reports a problem otherwise.
    @discardableResult
    private func checkAuthorization(forPage: Bool) -> Bool {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()   // updates start in locationManagerDidChangeAuthorization
            return false
        case .denied, .restricted:
            reportDenied()
            return false
        default:
            if manager.accuracyAuthorization == .reducedAccuracy {
                sendJS("window.KnoxNative && window.KnoxNative.onTrackingError('Turn on Precise Location for KnoxCanvas in Settings so houses can be matched.')")
            }
            return true
        }
    }

    private func reportDenied() {
        let msg = "Location is off for KnoxCanvas. Turn it on in Settings → KnoxCanvas → Location (While Using the App)."
        sendJS("window.KnoxNative && window.KnoxNative.onTrackingError(\(jsString(msg)))")
        sendJS("window.__knoxGeoError && window.__knoxGeoError(1, \(jsString(msg)))")
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if tracking || geoActive { manager.startUpdatingLocation() }
            sendJS("window.KnoxNative && window.KnoxNative.onTrackingOk && window.KnoxNative.onTrackingOk()")
        case .denied, .restricted:
            if tracking || geoActive { reportDenied() }
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let e = error as? CLError, e.code == .denied { reportDenied() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let inBackground = UIApplication.shared.applicationState != .active
        for loc in locations where loc.horizontalAccuracy >= 0 {
            if geoActive && !inBackground { deliverToGeo(loc) }
            guard tracking else { continue }
            buffer.append([
                "lat": loc.coordinate.latitude,
                "lng": loc.coordinate.longitude,
                "acc": loc.horizontalAccuracy,
                "spd": loc.speed,
                "t": (loc.timestamp.timeIntervalSince1970 * 1000).rounded()
            ])
            if inBackground { noteBackgroundWalking(loc) }
        }
        guard tracking else { return }
        if buffer.count > maxBuffer { buffer.removeFirst(buffer.count - maxBuffer) }
        saveBuffer()
        flush()
    }

    // MARK: - Delivering to the page

    private func flush() {
        guard pageReady, tracking, !flushing, !buffer.isEmpty, let webView,
              UIApplication.shared.applicationState == .active else { return }
        let batch = Array(buffer.prefix(500))
        guard let data = try? JSONSerialization.data(withJSONObject: batch),
              let json = String(data: data, encoding: .utf8) else { return }
        flushing = true
        webView.evaluateJavaScript("window.KnoxNative.onLocations(\(json)); true") { [weak self] _, error in
            guard let self else { return }
            self.flushing = false
            guard error == nil else { return }   // page not ready; keep the points for next time
            self.buffer.removeFirst(min(batch.count, self.buffer.count))
            self.saveBuffer(force: self.buffer.isEmpty)
            if !self.buffer.isEmpty { self.flush() }
        }
    }

    private func deliverToGeo(_ loc: CLLocation) {
        let c: [String: Double] = [
            "lat": loc.coordinate.latitude, "lng": loc.coordinate.longitude,
            "acc": loc.horizontalAccuracy, "spd": loc.speed, "hdg": loc.course,
            "t": (loc.timestamp.timeIntervalSince1970 * 1000).rounded()
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: c),
              let json = String(data: data, encoding: .utf8) else { return }
        sendJS("window.__knoxGeoDeliver && window.__knoxGeoDeliver(\(json))")
    }

    private func sendJS(_ js: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js + "; true", completionHandler: nil)
        }
    }

    private func jsString(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        let arr = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(arr.dropFirst().dropLast())   // ["text"] -> "text"
    }

    private var lastSave = Date.distantPast
    /// Persist pending points so they survive the app being closed. Throttled while walking.
    private func saveBuffer(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastSave) > 15 else { return }
        lastSave = Date()
        UserDefaults.standard.set(buffer, forKey: bufferKey)
    }

    // MARK: - Background reminder

    /// With the phone in a pocket the page can't show its prompt, so every ~250 m of
    /// walking send a quiet notification reminding them to open the app and mark houses.
    private func noteBackgroundWalking(_ loc: CLLocation) {
        guard loc.horizontalAccuracy <= 35 else { return }
        if let last = lastBgLocation {
            let d = loc.distance(from: last)
            let dt = loc.timestamp.timeIntervalSince(last.timestamp)
            if dt > 0 && d / dt < 3.5 { bgDistance += d }   // walking only, not driving
        }
        lastBgLocation = loc
        guard bgDistance >= notifyEveryMeters, Date().timeIntervalSince(lastNotifyAt) >= notifyMinInterval else { return }
        lastNotifyAt = Date()
        let feet = Int(bgDistance * 3.281)
        bgDistance = 0
        let content = UNMutableNotificationContent()
        content.title = "Mark the houses you passed"
        content.body = "You've walked about \(feet) ft. Open KnoxCanvas to drop door hanger pins on that street."
        content.sound = nil
        let req = UNNotificationRequest(identifier: "knox-walk", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    @objc private func appWillResignActive() {
        saveBuffer(force: true)
    }

    @objc private func appDidBecomeActive() {
        bgDistance = 0
        lastBgLocation = nil
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["knox-walk"])
        flush()
    }
}
