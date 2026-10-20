import Foundation
import MapKit

/// Address autocomplete with MKLocalSearchCompleter, biased to what's on screen.
@MainActor @Observable
final class AddressSearch: NSObject, MKLocalSearchCompleterDelegate {
    var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func update(_ query: String, region: MKCoordinateRegion?) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3 else { results = []; completer.cancel(); return }
        if let region { completer.region = region }
        completer.queryFragment = q
    }

    func clear() { results = []; completer.cancel() }

    /// Looks up a picked suggestion's coordinate and a "123 Main St, Knoxville, TN" label.
    func resolve(_ c: MKLocalSearchCompletion) async -> (CLLocationCoordinate2D, String)? {
        guard let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: c)).start().mapItems.first else { return nil }
        let label = [c.title, c.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
        return (item.placemark.coordinate, label)
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let r = Array(completer.results.prefix(6))
        Task { @MainActor in self.results = r }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }
}
