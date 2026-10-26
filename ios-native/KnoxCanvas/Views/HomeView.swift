import SwiftUI
import MapKit

/// The map screen: floating search, filter chips with counts, sync status and the bottom
/// tab bar, laid out like the redesigned web app.
struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @State private var store: PinStore?
    @State private var shifts: ShiftStore?
    @State private var people: People?
    @State private var doorline: DoorlineStore?

    /// A Doorline crew member picking other businesses under "Hanging for" gets new stores.
    private var storeKey: String { "\(session.companyId ?? "")|\(session.workIds.joined(separator: ","))" }

    var body: some View {
        Group {
            if let store, let shifts, let people, let doorline {
                MapScreen(store: store, shifts: shifts, people: people, doorline: doorline)
            } else { Theme.bg.ignoresSafeArea() }
        }
        .task(id: storeKey) {
            guard let cid = session.companyId, let uid = session.user?.uid else { return }
            shifts?.pause()
            store?.stop()
            let sheets = session.company?.sheetsUrl ?? ""
            let work = session.isClient ? [] : session.workIds
            let s = PinStore(companyId: cid, workIds: work, uid: uid, sheetsUrl: sheets)
            s.start()
            let sh = ShiftStore(companyId: cid, clientIds: work, clientLabel: session.workLabel, uid: uid,
                                userName: session.profile?.name ?? "", sheetsUrl: sheets, pins: s)
            let pe = People(uid: uid, selfName: session.profile?.name ?? "")
            let dl = DoorlineStore(workIds: s.workIds, uid: uid)
            store = s
            shifts = sh
            people = pe
            doorline = dl
            Task { await pe.load(companyId: cid) }
            Task { await dl.load() }
            await sh.start()
        }
        .onDisappear { shifts?.pause(); store?.stop(); store = nil; shifts = nil; people = nil; doorline = nil }
        // Owner edited company settings: new Sheets syncs go to the new URL.
        .onChange(of: session.company?.sheetsUrl) { _, url in
            store?.sheetsUrl = url ?? ""
            shifts?.sheetsUrl = url ?? ""
        }
    }
}

private struct SelectedPin: Identifiable { let id: String }

struct MapScreen: View {
    @Environment(SessionStore.self) private var session
    @Bindable var store: PinStore
    let shifts: ShiftStore
    let people: People
    let doorline: DoorlineStore
    @State private var controller = MapController()
    @State private var pathsOn = false
    @State private var framedRoutes = false
    @State private var search = AddressSearch()
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var selected: SelectedPin?
    @State private var panel: Panel?
    @State private var toastText: String?
    @State private var tools = MapTools()
    @State private var zoneName = ""
    @State private var zoneYear = ""
    @State private var packs = StatePacks.shared
    @AppStorage("knoxBasemap") private var basemapRaw = Basemap.street.rawValue
    @AppStorage("knoxColorBy") private var colorByRaw = ColorBy.status.rawValue

    enum Panel: String, Identifiable { case shift, layers, account, sweep, team, metrics, route, export, admin, houseData, companyStates, hangers, routes; var id: String { rawValue } }

    private var basemap: Basemap { Basemap(rawValue: basemapRaw) ?? .street }
    private var colorBy: ColorBy { ColorBy(rawValue: colorByRaw) ?? .status }

    var body: some View {
        ZStack(alignment: .top) {
            PinMapView(store: store, controller: controller, basemap: basemap,
                       version: store.version, hidden: store.hidden,
                       colorBy: colorBy, people: people, peopleVersion: people.version,
                       hasFrame: store.initialFrame != nil,
                       sweep: shifts.sweep, sweepVersion: shifts.sweep.version,
                       tools: tools, toolsKey: toolsKey, doorline: doorline,
                       onTapPin: { open($0) }, onTapCandidate: { shifts.sweep.toggle($0) }, onTapMap: tapMap)
                .ignoresSafeArea()

            LinearGradient(colors: [Theme.bg.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 140).ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 8) {
                if tools.drawing != .off {
                    DrawToolbar(tools: tools, name: $zoneName, year: $zoneYear, cancel: tools.stopDrawing, finish: finishDrawing)
                } else {
                    searchCard
                    if searchFocused && !search.results.isEmpty { suggestions } else {
                        if session.isClient { clientCount } else {
                            chips
                            if colorBy == .person { peopleChips }
                        }
                        statusRow
                    }
                }
                Spacer(minLength: 0)
                if !shifts.sweep.candidates.isEmpty {
                    SweepBanner(sweep: shifts.sweep) { panel = .sweep }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 8)
                }
                if let toastText {
                    Toast(text: toastText)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 10)
                }
                TabBar(clockInTime: shifts.clockInTime, drawing: tools.drawing == .zone, client: session.isClient, select: tab)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toastText)
        .onChange(of: store.version, initial: true) { people.update(from: store.pins) }
        .onChange(of: session.company?.states ?? [], initial: false) { _, codes in packs.ensure(codes) }
        .onChange(of: shifts.clockedIn, initial: true) { _, on in session.workLocked = on }
        .onChange(of: pathsOn) { _, on in
            if on { Task { showToast(await doorline.showPaths()) } } else { doorline.hidePaths() }
        }
        // No hangers yet: show the routes instead.
        .onChange(of: doorline.version) {
            guard !framedRoutes, store.pins.isEmpty, let r = doorline.allBounds else { return }
            framedRoutes = true
            controller.show(r)
        }
        .task { await setUpHouseData() }
        .animation(.easeInOut(duration: 0.25), value: shifts.sweep.candidates.isEmpty)
        // Again whenever the stores are replaced (a crew member switched businesses).
        .onChange(of: ObjectIdentifier(store), initial: true) {
            controller.onMessage = { showToast($0) }
            store.toast = { showToast($0) }
            shifts.toast = { showToast($0) }
            shifts.sweep.toast = { showToast($0) }
        }
        .sheet(item: $selected) { sel in
            PinSheet(store: store, people: people, pinId: sel.id, readOnly: session.isClient, toast: showToast) { selected = nil }
                .presentationDetents([.fraction(0.62), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.bg)
        }
        .sheet(item: $panel) { p in
            switch p {
            case .shift:
                ShiftSheet(shifts: shifts).presentationDetents([.large])
            case .sweep:
                SweepReviewSheet(sweep: shifts.sweep).presentationDetents([.medium, .large])
            case .layers:
                LayersSheet(basemap: $basemapRaw, colorBy: $colorByRaw, tools: tools, zipAdded: { rect in
                    panel = nil
                    controller.show(rect)
                }, toast: showToast)
                .presentationDetents([.medium, .large])
            case .account:
                AccountSheet(clockedIn: shifts.clockedIn) { panel = $0 }.presentationDetents([.medium, .large])
            case .route:
                RouteSheet(tools: tools, pins: store, drawZone: {
                    panel = nil
                    startDrawing(forRoute: true)
                }, viewOnMap: {
                    panel = nil
                    let pts = (tools.routeFrom.map { [$0.coordinate] } ?? []) + tools.route.map(\.coordinate)
                    controller.frame(pts, animated: true)
                }, toast: showToast)
                .presentationDetents([.medium, .large])
            case .export:
                ExportSheet(pins: store).presentationDetents([.large])
            case .admin:
                AdminSheet(uid: store.uid, homeCompanyId: store.companyId).presentationDetents([.large])
            case .houseData:
                HouseDataSheet(companyStates: session.company?.states ?? []).presentationDetents([.large])
            case .companyStates:
                CompanyStatesSheet(initial: []) { picked in
                    let team = TeamStore(companyId: store.companyId, uid: store.uid)
                    try await team.saveStates(picked)
                    session.applyCompanyStates(picked)
                    packs.ensure(picked)
                }
                .presentationDetents([.large])
                .interactiveDismissDisabled(false)
            case .hangers:
                HangersSheet(pins: store, doorline: doorline, pathsOn: $pathsOn, show: { r in
                    panel = nil
                    controller.show(r)
                }, toast: showToast)
                .presentationDetents([.large])
            case .routes:
                RoutesSheet(pins: store, doorline: doorline, draw: {
                    panel = nil
                    selected = nil
                    zoneName = ""
                    tools.startDrawing(.area)
                }, show: { r in
                    panel = nil
                    controller.show(r)
                }, toast: showToast)
                .presentationDetents([.medium, .large])
            case .team:
                TeamSheet(companyId: store.companyId, uid: store.uid).presentationDetents([.large])
            case .metrics:
                MetricsSheet(pins: store, companyId: store.companyId, uid: store.uid).presentationDetents([.large])
            }
        }
    }

    // MARK: Search

    private var searchCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.muted)
            TextField("", text: $query, prompt: Text("Search an address").foregroundStyle(Theme.muted))
                .focused($searchFocused)
                .font(.system(size: 17)).foregroundStyle(Theme.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { if let first = search.results.first { pick(first) } }
                .onChange(of: query) { _, q in search.update(q, region: controller.map?.region) }
            if !query.isEmpty {
                Button { query = ""; search.clear() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(Theme.muted)
                        .frame(width: 36, height: 44)
                }
                .accessibilityLabel("Clear search")
            }
            Button { controller.locate() } label: {
                Image(systemName: "location.fill").font(.system(size: 18)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("My location")
        }
        .padding(.leading, 14).padding(.trailing, 4)
        .frame(height: 52)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private var suggestions: some View {
        VStack(spacing: 0) {
            ForEach(Array(search.results.enumerated()), id: \.offset) { i, r in
                Button { pick(r) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                        if !r.subtitle.isEmpty {
                            Text(r.subtitle).font(.system(size: 14)).foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < search.results.count - 1 { Divider().overlay(Theme.border) }
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border))
        .padding(.horizontal, 12)
    }

    private func pick(_ r: MKLocalSearchCompletion) {
        searchFocused = false
        query = ""
        search.clear()
        Task {
            guard let (c, label) = await search.resolve(r) else { showToast("No matches"); return }
            controller.center(on: c, meters: 120)
            if session.isClient { return } // clients look; the crew places pins
            let id = store.createPin(at: c, addr: label)
            try? await Task.sleep(for: .milliseconds(250))
            open(id)
        }
    }

    // MARK: Filters and status

    /// Doorline client: one count instead of the status filters.
    private var clientCount: some View {
        let n = store.counts[.hanger] ?? 0
        return HStack {
            Button { panel = .hangers } label: {
                HStack(spacing: 8) {
                    Circle().fill(PinStatus.hanger.color).frame(width: 10, height: 10)
                    Text("\(n)").monospacedDigit().foregroundStyle(PinStatus.hanger.color)
                    Text(n == 1 ? "door hanger" : "door hangers").foregroundStyle(Theme.text)
                }
                .font(.system(size: 16, weight: .bold))
                .padding(.horizontal, 15).frame(height: 40)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.08)))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 12)
    }

    private var chips: some View {
        let counts = store.counts
        let total = counts.values.reduce(0, +)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Chip(label: "All", count: total, color: nil, active: store.hidden.isEmpty) { store.hidden = [] }
                ForEach([PinStatus.hanger, .interest, .no, .dnr, .none]) { s in
                    Chip(label: s.chipLabel, count: counts[s] ?? 0, color: s.color, active: !store.hidden.contains(s)) {
                        if store.hidden.contains(s) { store.hidden.remove(s) } else { store.hidden.insert(s) }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
    }

    /// Person view: one chip per person, counting the pins the status chips let through.
    private var peopleChips: some View {
        var counts: [String: Int] = [:]
        for p in store.pins.values where !store.hidden.contains(p.status) { counts[people.key(p), default: 0] += 1 }
        let keys = people.order.filter { counts[$0] != nil || $0 == people.uid }
            + (counts[People.unknown] != nil ? [People.unknown] : [])
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Chip(label: "Everyone", count: counts.values.reduce(0, +), color: nil, active: people.hidden.isEmpty) {
                    people.hidden = []
                }
                ForEach(keys, id: \.self) { k in
                    Chip(label: people.shortName(k), count: counts[k] ?? 0, color: people.color(k), active: !people.hidden.contains(k)) {
                        people.toggle(k)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder private var statusRow: some View {
        if store.sync != .ok || shifts.clockedIn || packs.isDownloading || !session.workIds.isEmpty {
            HStack(spacing: 6) {
                if let (code, p) = packs.progress.first {
                    Button { panel = .houseData } label: {
                        StatusPill(text: "Downloading \(packs.name(code)) houses \(Int(p * 100))%", color: Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
                if store.sync != .ok {
                    StatusPill(text: syncText, color: store.sync == .error ? PinStatus.no.color : PinStatus.hanger.color)
                }
                switch shifts.sweep.gps {
                case .on: StatusPill(text: "GPS", color: PinStatus.interest.color)
                case .warn: StatusPill(text: "GPS off", color: PinStatus.no.color)
                case .off: EmptyView()
                }
                if let start = shifts.clockInTime {
                    Button { panel = .shift } label: {
                        TimelineView(.periodic(from: .now, by: 15)) { ctx in
                            let ms = Int64(ctx.date.timeIntervalSince1970 * 1000) - start
                            StatusPill(text: "On shift \(ShiftFormat.short(ms)) \u{00B7} \(shifts.hangersSince(start)) hangers",
                                       color: PinStatus.interest.color)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open shift")
                }
                if !session.workIds.isEmpty {
                    Button { panel = .shift } label: {
                        StatusPill(text: "For \(session.workLabel)", color: PinStatus.hanger.color).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hanging for \(session.workLabel)")
                }
                Spacer()
            }
            .padding(.horizontal, 12)
        }
    }

    private var syncText: String {
        switch store.sync {
        case .ok: "Synced"
        case .pending: "Saving\u{2026}"
        case .offline: "Offline \u{00B7} saved on device"
        case .error: "Sync error"
        }
    }

    // MARK: Actions

    /// Read here so SwiftUI updates the map when any tool layer changes.
    private var toolsKey: String {
        "\(tools.drawVersion)-\(tools.routeVersion)-\(tools.zipVersion)-\(tools.showZones)-\(store.zonesVersion)-\(doorline.version)-\(doorline.pathsVersion)"
    }

    /// Downloads the company's states. With none picked yet, the owner is asked once, and
    /// everyone else gets the state they're standing in.
    private func setUpHouseData() async {
        guard !session.isClient else { return } // clients don't canvass
        await packs.loadManifest()
        let codes = session.company?.states ?? []
        if !codes.isEmpty { packs.ensure(codes); return }
        let askedKey = "knoxStatesAsked_\(store.companyId)"
        if session.profile?.isOwner == true, !UserDefaults.standard.bool(forKey: askedKey) {
            UserDefaults.standard.set(true, forKey: askedKey)
            try? await Task.sleep(for: .seconds(1))
            if panel == nil && selected == nil { panel = .companyStates }
        } else if packs.installed.isEmpty, let here = await StatePacks.currentState() {
            packs.ensure([here])
        }
    }

    private func startDrawing(forRoute: Bool) {
        selected = nil
        searchFocused = false
        zoneName = ""
        zoneYear = ""
        tools.startDrawing(forRoute: forRoute)
    }

    private func finishDrawing() {
        let poly = tools.drawn
        guard poly.count >= 3 else { showToast("Tap at least 3 points"); return }
        if tools.drawing == .area {
            let trimmed = zoneName.trimmingCharacters(in: .whitespaces)
            let name = trimmed.isEmpty ? "Neighborhood \(doorline.drawnCount + 1)" : trimmed
            doorline.addDrawn(name: name, points: poly)
            tools.stopDrawing()
            panel = .routes
            showToast("\u{201C}\(name)\u{201D} added")
            return
        }
        if tools.drawing == .route {
            tools.setRouteZone(poly, pins: store)
            tools.stopDrawing()
            panel = .route
            showToast("Route zone set")
            return
        }
        let year = zoneYear.trimmingCharacters(in: .whitespaces)
        guard !year.isEmpty else { showToast("Enter the year built first"); return }
        let trimmed = zoneName.trimmingCharacters(in: .whitespaces)
        let name = trimmed.isEmpty ? "Zone \(store.zones.count + 1)" : trimmed
        let count = store.addPolygonZone(name: name, year: year, polygon: poly)
        tools.stopDrawing()
        showToast("\u{201C}\(name)\u{201D} saved \u{00B7} \(count) pins updated")
    }

    private func tapMap(_ c: CLLocationCoordinate2D) {
        if searchFocused { searchFocused = false; return }
        if tools.drawing != .off { tools.addPoint(c); return }
        if session.isClient { return } // clients look; the crew places pins
        open(store.createPin(at: c))
    }

    private func open(_ id: String) {
        // While outlining, tapping a pin uses it as a corner.
        if tools.drawing != .off {
            if let p = store.pins[id] { tools.addPoint(p.coordinate) }
            return
        }
        searchFocused = false
        selected = SelectedPin(id: id)
    }

    private func tab(_ t: TabBar.Tab) {
        switch t {
        case .shift: panel = .shift
        case .route: panel = .route
        case .zone: if tools.drawing == .off { startDrawing(forRoute: false) } else { tools.stopDrawing() }
        case .layers: panel = .layers
        case .account: panel = .account
        case .hangers: panel = .hangers
        case .routes: if tools.drawing == .off { panel = .routes } else { tools.stopDrawing() }
        }
    }

    private func showToast(_ text: String) {
        toastText = text
        let current = text
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            if toastText == current { toastText = nil }
        }
    }
}

extension PinStatus {
    /// Short names for the filter chips.
    var chipLabel: String {
        switch self {
        case .none: "Not visited"
        case .hanger: "Hanger"
        case .interest: "Interested"
        case .no: "Not interested"
        case .dnr: "Do not return"
        }
    }
}

private struct Chip: View {
    let label: String
    let count: Int
    let color: Color?
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let color { Circle().fill(color).frame(width: 10, height: 10) }
                Text(label).foregroundStyle(Theme.text)
                Text("\(count)").monospacedDigit()
                    .foregroundStyle(color == nil && active ? .white.opacity(0.8) : Theme.muted)
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 13)
            .frame(height: 38)
            .background(color == nil && active ? Theme.accent : Theme.card, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.08)))
            .opacity(color != nil && !active ? 0.4 : 1)
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

private struct StatusPill: View {
    let text: String
    let color: Color
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.system(size: 13, weight: .bold)).foregroundStyle(color)
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(Theme.card, in: Capsule())
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
    }
}

struct TabBar: View {
    enum Tab: CaseIterable { case shift, route, zone, layers, account, hangers, routes }
    let clockInTime: Int64?
    var drawing = false
    /// Doorline client: Hangers / Routes / Layers / Account.
    var client = false
    let select: (Tab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            if client {
                item(.hangers, "Hangers", "house")
                item(.routes, "Routes", "pentagon")
            } else {
                // While on shift the tab shows the running time, like the web.
                TimelineView(.periodic(from: .now, by: 15)) { ctx in
                    let label = clockInTime.map { ShiftFormat.short(Int64(ctx.date.timeIntervalSince1970 * 1000) - $0) } ?? "Clock in"
                    item(.shift, label, "timer", active: clockInTime != nil)
                }
                item(.route, "Route", "point.topleft.down.to.point.bottomright.curvepath")
                item(.zone, "Zone", "pentagon", active: drawing)
            }
            item(.layers, "Layers", "square.3.layers.3d")
            item(.account, "Account", "person.crop.circle")
        }
        .padding(.horizontal, 4)
        .frame(height: 58)
        .background(Color(hex: 0x151720).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func item(_ t: Tab, _ label: String, _ icon: String, active: Bool = false) -> some View {
        Button { select(t) } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 21, weight: .medium))
                Text(label).font(.system(size: 11, weight: .semibold)).lineLimit(1).monospacedDigit()
            }
            .foregroundStyle(active ? Theme.accent : Theme.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct AccountSheet: View {
    @Environment(SessionStore.self) private var session
    var clockedIn = false
    var open: (MapScreen.Panel) -> Void = { _ in }
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var deleteError = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Account").font(.title2.bold()).foregroundStyle(Theme.text)
                row("Name", session.profile?.name)
                row("Email", session.user?.email)
                row("Company", session.company?.name)
                row("Role", session.profile?.role)
                if session.profile?.isOwner == true && !session.isClient {
                    Text("OWNER TOOLS").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted).padding(.top, 8)
                    menuItem("Team and company settings", "person.2.fill") { open(.team) }
                    menuItem("Team metrics", "chart.bar.fill") { open(.metrics) }
                }
                if session.isAdmin {
                    Text("KNOXCANVAS").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted).padding(.top, 8)
                    menuItem("Admin: companies and Doorline crews", "building.2.fill") { open(.admin) }
                }
                Text("DATA").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted).padding(.top, 8)
                if session.isClient {
                    menuItem("Your door hangers (CSV)", "house.fill") { open(.hangers) }
                } else {
                    menuItem("House data (states)", "house.fill") { open(.houseData) }
                    menuItem("Export pins (CSV)", "square.and.arrow.up") { open(.export) }
                }
                KnoxButton(title: "Sign out", style: .ghost) {
                    if clockedIn { confirmSignOut = true } else { session.signOut() }
                }
                .padding(.top, 10)
                MessageText(error: deleteError, info: "")
                Button(deleting ? "Deleting\u{2026}" : "Delete account") {
                    deleteError = ""
                    if clockedIn { deleteError = "Clock out first, then delete your account." } else { confirmDelete = true }
                }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.error)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(deleting)
            }
            .padding(20)
        }
        .confirmationDialog("You\u{2019}re still clocked in. Sign out anyway?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { session.signOut() }
        } message: {
            Text("Your shift keeps running and picks back up when you sign in again.")
        }
        .confirmationDialog("Permanently delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { deleteAccount() }
        } message: {
            Text("This can\u{2019}t be undone.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
    }

    private func menuItem(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Theme.accent).frame(width: 26)
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: Theme.tapHeight)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func deleteAccount() {
        deleting = true
        Task {
            defer { deleting = false }
            do { try await session.deleteAccount() }
            catch { deleteError = error.localizedDescription }
        }
    }

    private func row(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.muted)
            Spacer()
            Text(value ?? "").foregroundStyle(Theme.text)
        }
        .font(.system(size: 17))
    }
}
