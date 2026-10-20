import Foundation
import CoreLocation

/// Reverse geocoding: Google through the Cloudflare Worker (same as the web), then Apple's
/// geocoder, then plain coordinates so the pin always gets a label.
enum Geocoder {
    static func address(for c: CLLocationCoordinate2D) async -> String {
        if let a = await worker(c) { return a }
        if let a = await apple(c) { return a }
        return String(format: "%.4f, %.4f", c.latitude, c.longitude)
    }

    private struct GoogleResponse: Decodable {
        struct Result: Decodable {
            struct Geometry: Decodable { let location_type: String? }
            let formatted_address: String?
            let geometry: Geometry?
        }
        let status: String
        let results: [Result]?
    }

    private static func worker(_ c: CLLocationCoordinate2D) async -> String? {
        var comps = URLComponents(url: AppConfig.geocodeWorker, resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "lat", value: String(c.latitude)), .init(name: "lng", value: String(c.longitude))]
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 10
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let r = try? JSONDecoder().decode(GoogleResponse.self, from: data),
              r.status == "OK", let results = r.results, !results.isEmpty else { return nil }
        let best = results.first { ["ROOFTOP", "RANGE_INTERPOLATED"].contains($0.geometry?.location_type ?? "") } ?? results[0]
        let a = best.formatted_address ?? ""
        return a.isEmpty ? nil : a
    }

    private static func apple(_ c: CLLocationCoordinate2D) async -> String? {
        guard let p = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude)).first,
              let num = p.subThoroughfare, let road = p.thoroughfare else { return nil }
        let stateZip = [p.administrativeArea, p.postalCode].compactMap { $0 }.joined(separator: " ")
        return ["\(num) \(road)", p.locality, stateZip.isEmpty ? nil : stateZip].compactMap { $0 }.joined(separator: ", ")
    }
}
