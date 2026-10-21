import SwiftUI
import MapKit

enum Basemap: String { case street, sat }

/// Lets SwiftUI move the camera without owning the MKMapView.
@MainActor
final class MapController: NSObject, CLLocationManagerDelegate {
    weak var map: MKMapView?
    var onMessage: (String) -> Void = { _ in }
    private let location = CLLocationManager()
    private var pendingLocate = false

    override init() {
        super.init()
        location.delegate = self
    }

    func center(on c: CLLocationCoordinate2D, meters: Double = 180) {
        map?.setRegion(MKCoordinateRegion(center: c, latitudinalMeters: meters, longitudinalMeters: meters), animated: true)
    }

    /// Frames these points, never closer than about street level (the web's maxZoom 17).
    func frame(_ coords: [CLLocationCoordinate2D], animated: Bool) {
        guard let map, !coords.isEmpty else { return }
        var rect = MKMapRect.null
        for c in coords { rect = rect.union(MKMapRect(origin: MKMapPoint(c), size: MKMapSize(width: 1, height: 1))) }
        let minSide = 350 * MKMapPointsPerMeterAtLatitude(coords[0].latitude)
        if rect.size.width < minSide || rect.size.height < minSide {
            rect = rect.insetBy(dx: -(max(0, minSide - rect.size.width) / 2), dy: -(max(0, minSide - rect.size.height) / 2))
        }
        map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 190, left: 40, bottom: 120, right: 40), animated: animated)
    }

    func show(_ rect: MKMapRect) {
        guard let map, !rect.isNull else { return }
        map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 190, left: 30, bottom: 120, right: 30), animated: true)
    }

    func locate() {
        switch location.authorizationStatus {
        case .notDetermined:
            pendingLocate = true
            location.requestWhenInUseAuthorization()
        case .denied, .restricted:
            onMessage("Couldn\u{2019}t get your location \u{2014} allow location access in Settings")
        default:
            map?.showsUserLocation = true
            if let loc = map?.userLocation.location, -loc.timestamp.timeIntervalSinceNow < 30 {
                center(on: loc.coordinate)
            } else {
                pendingLocate = true
                onMessage("Finding your location\u{2026}")
            }
        }
    }

    /// Show the blue dot from launch if permission was already granted.
    func showUserIfAllowed() {
        let s = location.authorizationStatus
        map?.showsUserLocation = s == .authorizedWhenInUse || s == .authorizedAlways
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                map?.showsUserLocation = true
            case .denied, .restricted:
                if pendingLocate { onMessage("Couldn\u{2019}t get your location \u{2014} allow location access in Settings") }
                pendingLocate = false
            default: break
            }
        }
    }

    func userLocationUpdated(_ c: CLLocationCoordinate2D) {
        guard pendingLocate else { return }
        pendingLocate = false
        center(on: c)
    }
}

final class PinAnnotation: NSObject, MKAnnotation {
    let id: String
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var status: PinStatus

    init(_ p: Pin) {
        id = p.id
        coordinate = p.coordinate
        status = p.status
    }
}

/// A colored dot like the web's circleMarker, with a larger invisible tap area.
final class PinDotView: MKAnnotationView {
    static let reuseID = "pin"
    private static let size: CGFloat = 16

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: Self.size, height: Self.size)
        layer.cornerRadius = Self.size / 2
        layer.borderColor = UIColor.white.cgColor
        layer.borderWidth = 2
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 1.5
        layer.shadowOffset = .zero
        clusteringIdentifier = "pin"
        collisionMode = .circle
        displayPriority = .defaultHigh
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        refresh()
    }

    func refresh() {
        guard let a = annotation as? PinAnnotation else { return }
        backgroundColor = UIColor(a.status.color)
    }

    /// Fingers are bigger than 16 pt: accept taps within 22 pt of the center.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -14, dy: -14).contains(point)
    }
}

/// Overlapping dots merge into a count, colored by the most common status inside.
final class PinClusterView: MKAnnotationView {
    static let reuseID = "cluster"
    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 34, height: 34)
        layer.cornerRadius = 17
        layer.borderColor = UIColor.white.cgColor
        layer.borderWidth = 2
        label.frame = bounds
        label.textAlignment = .center
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .bold)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        addSubview(label)
        collisionMode = .circle
        displayPriority = .defaultHigh
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        guard let cluster = annotation as? MKClusterAnnotation else { return }
        let members = cluster.memberAnnotations.compactMap { $0 as? PinAnnotation }
        label.text = members.count > 999 ? "999+" : "\(members.count)"
        var tally: [PinStatus: Int] = [:]
        for m in members { tally[m.status, default: 0] += 1 }
        let top = tally.max { $0.value < $1.value }?.key ?? .none
        backgroundColor = UIColor(top.color)
    }
}

/// A house the street sweep found: a dashed ring, orange when it will be marked.
final class CandidateAnnotation: NSObject, MKAnnotation {
    let key: String
    let coordinate: CLLocationCoordinate2D
    var on: Bool

    init(_ c: Candidate) {
        key = c.key
        coordinate = CLLocationCoordinate2D(latitude: c.lat, longitude: c.lng)
        on = c.on
    }
}

final class CandidateRingView: MKAnnotationView {
    static let reuseID = "candidate"
    private let ring = CAShapeLayer()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        ring.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2)).cgPath
        ring.lineDashPattern = [4, 3]
        layer.addSublayer(ring)
        displayPriority = .required // never hidden or clustered
        zPriority = .max
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        refresh()
    }

    func refresh() {
        let on = (annotation as? CandidateAnnotation)?.on ?? true
        let color = on ? UIColor(PinStatus.hanger.color) : UIColor(PinStatus.none.color)
        ring.strokeColor = color.cgColor
        ring.fillColor = color.withAlphaComponent(on ? 0.35 : 0.1).cgColor
        ring.lineWidth = on ? 3 : 2
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -10, dy: -10).contains(point)
    }
}

/// Labels and markers for the map tools: zone names, zip codes, route stops, drawn corners.
/// They never take taps, so tapping on one still reaches the map.
final class BadgeAnnotation: NSObject, MKAnnotation {
    enum Kind { case label(String, UIColor), start, stop(Int), vertex }
    let coordinate: CLLocationCoordinate2D
    let kind: Kind
    init(_ c: CLLocationCoordinate2D, _ kind: Kind) {
        coordinate = c
        self.kind = kind
    }
}

final class BadgeView: MKAnnotationView {
    static let reuseID = "badge"
    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        isEnabled = false
        isUserInteractionEnabled = false
        canShowCallout = false
        label.textAlignment = .center
        label.textColor = .white
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        guard let a = annotation as? BadgeAnnotation else { return }
        layer.borderWidth = 0
        label.isHidden = false
        collisionMode = .rectangle
        switch a.kind {
        case let .label(text, color):
            label.text = text
            label.font = .systemFont(ofSize: 12, weight: .bold)
            label.textColor = .white
            let w = min(220, label.intrinsicContentSize.width + 16)
            frame = CGRect(x: 0, y: 0, width: w, height: 22)
            layer.cornerRadius = 11
            backgroundColor = color
            displayPriority = .defaultHigh
            zPriority = .defaultUnselected
        case .start:
            label.text = "S"
            label.font = .systemFont(ofSize: 12, weight: .heavy)
            label.textColor = UIColor(Theme.accent)
            frame = CGRect(x: 0, y: 0, width: 26, height: 26)
            layer.cornerRadius = 13
            layer.borderWidth = 3
            layer.borderColor = UIColor(Theme.accent).cgColor
            backgroundColor = .white
            displayPriority = .required
            zPriority = .max
        case let .stop(n):
            label.text = "\(n)"
            label.font = .systemFont(ofSize: n > 99 ? 10 : 12, weight: .bold)
            label.textColor = .white
            frame = CGRect(x: 0, y: 0, width: 26, height: 26)
            layer.cornerRadius = 13
            backgroundColor = UIColor(PinStatus.hanger.color)
            // Stops often sit right on a saved pin; the number has to win.
            displayPriority = .required
            zPriority = .defaultSelected
        case .vertex:
            label.isHidden = true
            frame = CGRect(x: 0, y: 0, width: 14, height: 14)
            layer.cornerRadius = 7
            layer.borderWidth = 2
            layer.borderColor = UIColor.white.cgColor
            backgroundColor = UIColor(Theme.accent)
            displayPriority = .required
            zPriority = .max
        }
        label.frame = bounds
    }
}

struct PinMapView: UIViewRepresentable {
    let store: PinStore
    let controller: MapController
    let basemap: Basemap
    /// Passed in (not just read from the store) so SwiftUI re-runs updateUIView on every change.
    let version: Int
    let hidden: Set<PinStatus>
    let hasFrame: Bool
    let sweep: SweepTracker
    let sweepVersion: Int
    let tools: MapTools
    /// Changes whenever any tool layer, the saved zones or the roofing cutoff change.
    let toolsKey: String
    let roofCutoff: Int
    var onTapPin: (String) -> Void
    var onTapCandidate: (String) -> Void
    var onTapMap: (CLLocationCoordinate2D) -> Void

    static let knoxville = CLLocationCoordinate2D(latitude: 35.9606, longitude: -83.9207)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        map.showsCompass = false
        map.register(PinDotView.self, forAnnotationViewWithReuseIdentifier: PinDotView.reuseID)
        map.register(PinClusterView.self, forAnnotationViewWithReuseIdentifier: PinClusterView.reuseID)
        map.register(CandidateRingView.self, forAnnotationViewWithReuseIdentifier: CandidateRingView.reuseID)
        map.register(BadgeView.self, forAnnotationViewWithReuseIdentifier: BadgeView.reuseID)
        map.setRegion(MKCoordinateRegion(center: Self.knoxville, latitudinalMeters: 3000, longitudinalMeters: 3000), animated: false)

        // Single tap drops a pin. A do-nothing double tap that it waits on keeps
        // double-tap-to-zoom from also dropping a pin.
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        let doubleTap = UITapGestureRecognizer(target: nil, action: nil)
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator
        tap.delegate = context.coordinator
        tap.require(toFail: doubleTap)
        map.addGestureRecognizer(doubleTap)
        map.addGestureRecognizer(tap)

        controller.map = map
        controller.showUserIfAllowed()
        context.coordinator.applyBasemap(basemap, to: map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyBasemap(basemap, to: map)
        context.coordinator.syncAnnotations(map)
        context.coordinator.syncSweep(map)
        context.coordinator.syncTools(map)
        if let frame = store.initialFrame {
            DispatchQueue.main.async { [store, controller] in
                guard store.initialFrame != nil else { return }
                store.initialFrame = nil
                controller.frame(frame, animated: false)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: PinMapView
        private var annotations: [String: PinAnnotation] = [:]
        private var lastVersion = -1
        private var lastHidden: Set<PinStatus> = []
        private var basemap: Basemap?
        private var candidates: [String: CandidateAnnotation] = [:]
        private var trailLine: MKPolyline?
        private var trailCount = 0
        private var lastSweepVersion = -1

        /// Overlays and badges for one tool, swapped out as a group.
        private struct Layer {
            var overlays: [MKOverlay] = []
            var badges: [BadgeAnnotation] = []
        }
        private enum Style { case draw, drawLine, routeZone, routeLine, roofTarget, roofOther, zip(UIColor) }
        private var styles: [ObjectIdentifier: Style] = [:]
        private var drawLayer = Layer(), routeLayer = Layer(), roofLayer = Layer(), zipLayer = Layer()
        private var lastDraw = -1, lastRoute = -1, lastZip = -1
        private var lastRoof = ""

        init(_ parent: PinMapView) { self.parent = parent }

        func applyBasemap(_ b: Basemap, to map: MKMapView) {
            guard b != basemap else { return }
            basemap = b
            switch b {
            case .street:
                let c = MKStandardMapConfiguration()
                c.pointOfInterestFilter = .excludingAll
                map.preferredConfiguration = c
            case .sat:
                let c = MKHybridMapConfiguration()
                c.pointOfInterestFilter = .excludingAll
                map.preferredConfiguration = c
            }
        }

        /// Diffs the store's pins against the map's annotations.
        func syncAnnotations(_ map: MKMapView) {
            let store = parent.store
            guard store.version != lastVersion || store.hidden != lastHidden else { return }
            lastVersion = store.version
            lastHidden = store.hidden

            var add: [PinAnnotation] = []
            var remove: [PinAnnotation] = []
            for (id, a) in annotations {
                guard let p = store.pins[id], !store.hidden.contains(p.status) else {
                    remove.append(a)
                    annotations[id] = nil
                    continue
                }
                if a.coordinate.latitude != p.lat || a.coordinate.longitude != p.lng { a.coordinate = p.coordinate }
                if a.status != p.status {
                    a.status = p.status
                    (map.view(for: a) as? PinDotView)?.refresh()
                }
            }
            for (id, p) in store.pins where annotations[id] == nil && !store.hidden.contains(p.status) {
                let a = PinAnnotation(p)
                annotations[id] = a
                add.append(a)
            }
            if !remove.isEmpty { map.removeAnnotations(remove) }
            if !add.isEmpty { map.addAnnotations(add) }
        }

        /// Candidate rings and the walked trail.
        func syncSweep(_ map: MKMapView) {
            let sweep = parent.sweep
            guard sweep.version != lastSweepVersion else { return }
            lastSweepVersion = sweep.version

            var keep = Set<String>()
            var add: [CandidateAnnotation] = []
            for c in sweep.candidates {
                keep.insert(c.key)
                if let a = candidates[c.key] {
                    if a.on != c.on { a.on = c.on; (map.view(for: a) as? CandidateRingView)?.refresh() }
                } else {
                    let a = CandidateAnnotation(c)
                    candidates[c.key] = a
                    add.append(a)
                }
            }
            let remove = candidates.filter { !keep.contains($0.key) }
            for k in remove.keys { candidates[k] = nil }
            if !remove.isEmpty { map.removeAnnotations(Array(remove.values)) }
            if !add.isEmpty { map.addAnnotations(add) }

            if sweep.trail.count != trailCount {
                trailCount = sweep.trail.count
                if let trailLine { map.removeOverlay(trailLine) }
                trailLine = nil
                if sweep.trail.count > 1 {
                    let coords = sweep.trail.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
                    let line = MKPolyline(coordinates: coords, count: coords.count)
                    map.addOverlay(line, level: .aboveRoads)
                    trailLine = line
                }
            }
        }

        func syncTools(_ map: MKMapView) {
            let t = parent.tools
            if t.drawVersion != lastDraw {
                lastDraw = t.drawVersion
                var l = Layer()
                let pts = t.drawn
                if pts.count >= 3 { l.overlays.append(styled(MKPolygon(coordinates: pts, count: pts.count), .draw)) }
                if pts.count >= 2 { l.overlays.append(styled(MKPolyline(coordinates: pts, count: pts.count), .drawLine)) }
                l.badges = pts.map { BadgeAnnotation($0, .vertex) }
                replace(&drawLayer, with: l, on: map)
            }
            if t.routeVersion != lastRoute {
                lastRoute = t.routeVersion
                var l = Layer()
                if let z = t.routeZone { l.overlays.append(styled(MKPolygon(coordinates: z, count: z.count), .routeZone)) }
                if let from = t.routeFrom, !t.route.isEmpty {
                    let line = [from.coordinate] + t.route.map(\.coordinate)
                    l.overlays.append(styled(MKPolyline(coordinates: line, count: line.count), .routeLine))
                    l.badges.append(BadgeAnnotation(from.coordinate, .start))
                    l.badges += t.route.enumerated().map { BadgeAnnotation($1.coordinate, .stop($0 + 1)) }
                }
                replace(&routeLayer, with: l, on: map)
            }
            let roofKey = "\(t.roofing)-\(parent.store.zonesVersion)-\(parent.roofCutoff)"
            if roofKey != lastRoof {
                lastRoof = roofKey
                var l = Layer()
                if t.roofing {
                    for z in parent.store.zones {
                        guard let poly = z.polygon else { continue }
                        let target = (Int(z.year) ?? .max) <= parent.roofCutoff
                        let p = MKPolygon(coordinates: poly, count: poly.count)
                        l.overlays.append(styled(p, target ? .roofTarget : .roofOther))
                        let color = UIColor(Color(hex: target ? 0x10b981 : 0x6b7280))
                        l.badges.append(BadgeAnnotation(Self.center(of: p.boundingMapRect),
                                                        .label("\(z.name.isEmpty ? "Zone" : z.name) \u{00B7} \(z.year)", color)))
                    }
                }
                replace(&roofLayer, with: l, on: map)
            }
            if t.zipVersion != lastZip {
                lastZip = t.zipVersion
                var l = Layer()
                for z in t.zips where z.visible {
                    var rect = MKMapRect.null
                    for p in z.polygons {
                        l.overlays.append(styled(p, .zip(z.color)))
                        rect = rect.union(p.boundingMapRect)
                    }
                    l.badges.append(BadgeAnnotation(Self.center(of: rect), .label(z.code, z.color)))
                }
                replace(&zipLayer, with: l, on: map)
            }
        }

        private func styled<O: MKOverlay>(_ o: O, _ s: Style) -> O {
            styles[ObjectIdentifier(o)] = s
            return o
        }

        private func replace(_ old: inout Layer, with new: Layer, on map: MKMapView) {
            map.removeOverlays(old.overlays)
            map.removeAnnotations(old.badges)
            for o in old.overlays where !new.overlays.contains(where: { $0 === o }) { styles[ObjectIdentifier(o)] = nil }
            map.addOverlays(new.overlays, level: .aboveRoads)
            map.addAnnotations(new.badges)
            old = new
        }

        private static func center(of r: MKMapRect) -> CLLocationCoordinate2D {
            MKMapPoint(x: r.midX, y: r.midY).coordinate
        }

        func mapView(_ map: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let style = styles[ObjectIdentifier(overlay)] { return renderer(overlay, style) }
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: line)
            r.strokeColor = UIColor(Theme.accent).withAlphaComponent(0.45)
            r.lineWidth = 4
            r.lineCap = .round
            r.lineJoin = .round
            return r
        }

        private func renderer(_ o: MKOverlay, _ s: Style) -> MKOverlayRenderer {
            let r: MKOverlayPathRenderer
            if let p = o as? MKPolygon { r = MKPolygonRenderer(polygon: p) }
            else if let l = o as? MKPolyline { r = MKPolylineRenderer(polyline: l) }
            else { return MKOverlayRenderer(overlay: o) }
            let accent = UIColor(Theme.accent), orange = UIColor(PinStatus.hanger.color)
            func set(_ c: UIColor, width: CGFloat, fill: CGFloat, dashed: Bool) {
                r.strokeColor = c
                r.fillColor = c.withAlphaComponent(fill)
                r.lineWidth = width
                r.lineDashPattern = dashed ? [6, 4] : nil
                r.lineJoin = .round
            }
            switch s {
            case .draw: set(accent, width: 2, fill: 0.1, dashed: false)
            case .drawLine: set(accent, width: 2, fill: 0, dashed: true)
            case .routeZone: set(orange, width: 2, fill: 0.1, dashed: true)
            case .routeLine:
                set(orange, width: 2.5, fill: 0, dashed: true)
                r.strokeColor = orange.withAlphaComponent(0.75)
            case .roofTarget: set(UIColor(Color(hex: 0x10b981)), width: 2.5, fill: 0.18, dashed: false)
            case .roofOther: set(UIColor(Color(hex: 0x6b7280)), width: 2.5, fill: 0.06, dashed: true)
            case let .zip(c): set(c, width: 2, fill: 0.08, dashed: true)
            }
            return r
        }

        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case is BadgeAnnotation:
                map.dequeueReusableAnnotationView(withIdentifier: BadgeView.reuseID, for: annotation)
            case is CandidateAnnotation:
                map.dequeueReusableAnnotationView(withIdentifier: CandidateRingView.reuseID, for: annotation)
            case is PinAnnotation:
                map.dequeueReusableAnnotationView(withIdentifier: PinDotView.reuseID, for: annotation)
            case is MKClusterAnnotation:
                map.dequeueReusableAnnotationView(withIdentifier: PinClusterView.reuseID, for: annotation)
            default:
                nil // the user's blue dot
            }
        }

        func mapView(_ map: MKMapView, didSelect annotation: MKAnnotation) {
            map.deselectAnnotation(annotation, animated: false)
            if annotation is BadgeAnnotation { return }
            if let a = annotation as? CandidateAnnotation {
                parent.onTapCandidate(a.key)
            } else if let a = annotation as? PinAnnotation {
                parent.onTapPin(a.id)
            } else if let c = annotation as? MKClusterAnnotation {
                map.showAnnotations(c.memberAnnotations, animated: true)
            }
        }

        func mapView(_ map: MKMapView, didUpdate userLocation: MKUserLocation) {
            if let c = userLocation.location?.coordinate { parent.controller.userLocationUpdated(c) }
        }

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let map = g.view as? MKMapView, g.state == .ended else { return }
            parent.onTapMap(map.convert(g.location(in: map), toCoordinateFrom: map))
        }

        /// Taps on a pin, cluster or the blue dot belong to MapKit, not to "drop a pin".
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var v = touch.view
            while let view = v {
                if view is MKAnnotationView { return false }
                if view is MKMapView { break }
                v = view.superview
            }
            return true
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
