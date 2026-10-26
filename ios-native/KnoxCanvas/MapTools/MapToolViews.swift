import SwiftUI
import MapKit

/// Replaces the search card while outlining a zone (the web's #zone-toolbar).
struct DrawToolbar: View {
    let tools: MapTools
    @Binding var name: String
    @Binding var year: String
    var cancel: () -> Void
    var finish: () -> Void
    @FocusState private var focus: Bool

    var body: some View {
        let forRoute = tools.drawing == .route, forArea = tools.drawing == .area
        VStack(alignment: .leading, spacing: 10) {
            Text(forArea ? "Outline the neighborhood you want hung \u{2014} tap its corners"
                 : forRoute ? "Outline the area to route \u{2014} tap its corners" : "Outline a neighborhood \u{2014} tap its corners")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
            if forArea {
                small("Neighborhood name", text: $name, keyboard: .default)
            } else if !forRoute {
                HStack(spacing: 8) {
                    small("Year built", text: $year, keyboard: .numberPad)
                    small("Name (optional)", text: $name, keyboard: .default)
                }
            }
            Text(tools.drawStatus).font(.system(size: 14)).foregroundStyle(Theme.muted)
            HStack(spacing: 8) {
                button("Undo", Theme.field, enabled: !tools.drawn.isEmpty) { tools.undoPoint() }
                button("Cancel", Theme.field) { focus = false; cancel() }
                button(forArea ? "\u{2713} Add route" : forRoute ? "\u{2713} Use zone" : "\u{2713} Save zone", Theme.accent, enabled: tools.drawn.count >= 3) {
                    focus = false
                    finish()
                }
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent))
        .shadow(color: Theme.accent.opacity(0.3), radius: 12, y: 4)
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private func small(_ placeholder: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Theme.muted))
            .focused($focus)
            .keyboardType(keyboard)
            .font(.system(size: 16)).foregroundStyle(Theme.text)
            .padding(.horizontal, 12).frame(height: 46)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }

    private func button(_ title: String, _ bg: Color, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(bg, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// The web's Route optimizer panel.
struct RouteSheet: View {
    let tools: MapTools
    let pins: PinStore
    var drawZone: () -> Void
    var viewOnMap: () -> Void
    var toast: (String) -> Void

    var body: some View {
        @Bindable var tools = tools
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Route optimizer").font(.title2.bold()).foregroundStyle(Theme.text)
                    Spacer()
                    Button("Clear") { tools.clearRoute(pins: pins); toast("Route cleared") }
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accent).frame(minHeight: 44)
                }
                status(pins.routeStart.map { "Start: \($0.addr)" } ?? "Tap a pin, then \u{201C}Set as route start\u{201D} \u{2014} or just draw a zone",
                       ready: pins.routeStart != nil)
                status(tools.routeZone.map { "Zone drawn \u{00B7} \($0.count) points" } ?? "No zone drawn", ready: tools.routeZone != nil)
                KnoxButton(title: "Draw route zone on map", style: .ghost, action: drawZone)
                VStack(spacing: 0) {
                    Toggle("Skip houses already visited", isOn: $tools.skipVisited).frame(minHeight: 50)
                    Divider().overlay(Theme.border)
                    Toggle("Skip do not return", isOn: $tools.skipDnr).frame(minHeight: 50)
                }
                .font(.system(size: 16)).foregroundStyle(Theme.text).tint(Theme.accent)
                .padding(.horizontal, 14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))

                KnoxButton(title: "Generate route", busyTitle: "Finding houses\u{2026}", busy: tools.routing) {
                    Task { toast(await tools.generateRoute(pins: pins)) }
                }
                if !tools.route.isEmpty { result }
            }
            .padding(20)
        }
        .background(Theme.bg)
    }

    private func status(_ text: String, ready: Bool) -> some View {
        Text(text).font(.system(size: 15)).foregroundStyle(ready ? Theme.text : Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ready ? PinStatus.interest.color.opacity(0.6) : Theme.border))
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 8) {
            if tools.routeFallback {
                status("Map data was unreachable \u{2014} routed through your saved pins instead.", ready: false)
            }
            Button(action: viewOnMap) {
                Text("View route on map").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: Theme.tapHeight)
                    .background(PinStatus.interest.color, in: RoundedRectangle(cornerRadius: Theme.radius))
            }
            .buttonStyle(.plain)
            Text("\(tools.route.count) stops \u{00B7} \(MapTools.formatDistance(tools.routeTotal)) total")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity).padding(.vertical, 4)
            if let from = tools.routeFrom {
                stopRow(Text("S").foregroundStyle(Theme.accent), bg: .white, from.addr, "")
            }
            LazyVStack(spacing: 6) {
                ForEach(Array(tools.route.enumerated()), id: \.element.id) { i, s in
                    stopRow(Text("\(i + 1)").foregroundStyle(.white), bg: PinStatus.hanger.color, s.addr,
                            MapTools.formatDistance(tools.leg(i)))
                }
            }
        }
    }

    private func stopRow(_ num: Text, bg: Color, _ addr: String, _ dist: String) -> some View {
        HStack(spacing: 12) {
            num.font(.system(size: 13, weight: .bold))
                .frame(width: 30, height: 30).background(bg, in: Circle())
            Text(addr).font(.system(size: 15)).foregroundStyle(Theme.text).lineLimit(2)
            Spacer()
            Text(dist).font(.system(size: 13)).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 12).frame(minHeight: 48)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Layers: basemap, pin colors, saved zones and zip code boundaries.
struct LayersSheet: View {
    @Binding var basemap: String
    @Binding var colorBy: String
    let tools: MapTools
    var zipAdded: (MKMapRect) -> Void
    var toast: (String) -> Void
    @State private var zip = ""
    @FocusState private var zipFocus: Bool

    var body: some View {
        @Bindable var tools = tools
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Map layers").font(.title2.bold()).foregroundStyle(Theme.text)
                heading("Map style")
                HStack(spacing: 8) {
                    seg("Street", Basemap.street)
                    seg("Satellite", Basemap.sat)
                }

                heading("Pin colors")
                HStack(spacing: 8) {
                    option("Status", on: colorBy == ColorBy.status.rawValue) { colorBy = ColorBy.status.rawValue }
                    option("Person", on: colorBy == ColorBy.person.rawValue) { colorBy = ColorBy.person.rawValue }
                }
                Text(colorBy == ColorBy.person.rawValue
                     ? "Each person has a color. Pins show who hung the hanger or marked the door; tap a pin for its status."
                     : "Pins show their status: door hanger, interested, not interested and so on.")
                    .font(.system(size: 14)).foregroundStyle(Theme.muted)

                heading("Neighborhood zones")
                Toggle(isOn: $tools.showZones) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show drawn zones").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                        Text("Outlines from the Zone tab, labeled with name and year")
                            .font(.system(size: 14)).foregroundStyle(Theme.muted)
                    }
                }
                .tint(Theme.accent)
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))

                heading("Zip code boundaries")
                HStack(spacing: 8) {
                    TextField("", text: $zip, prompt: Text("Zip code, e.g. 37923").foregroundStyle(Theme.muted))
                        .focused($zipFocus)
                        .keyboardType(.numberPad)
                        .font(.system(size: 16)).foregroundStyle(Theme.text)
                        .padding(.horizontal, 14).frame(height: 50)
                        .background(Theme.field, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                        .onChange(of: zip) { _, z in if z.count > 5 { zip = String(z.prefix(5)) } }
                    Button("Add", action: add)
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 72, height: 50)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                        .buttonStyle(.plain)
                }
                if let loading = tools.loadingZip {
                    HStack(spacing: 8) {
                        ProgressView().tint(Theme.muted)
                        Text("Loading \(loading)\u{2026}").foregroundStyle(Theme.muted)
                    }
                }
                FlowRow(tools.zips.map(\.code)) { code in zipTag(code) }
            }
            .padding(20)
        }
        .background(Theme.bg)
    }

    private func heading(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
    }

    private func add() {
        zipFocus = false
        let z = zip
        Task {
            if let err = await tools.addZip(z) { toast(err); return }
            zip = ""
            toast("\(z) added")
            if let added = tools.zips.last { zipAdded(Self.rect(added)) }
        }
    }

    static func rect(_ z: MapTools.Zip) -> MKMapRect {
        z.polygons.reduce(MKMapRect.null) { $0.union($1.boundingMapRect) }
    }

    @ViewBuilder private func zipTag(_ code: String) -> some View {
        if let z = tools.zips.first(where: { $0.code == code }) {
            let c = Color(uiColor: z.color)
            HStack(spacing: 0) {
                Button {
                    tools.toggleZip(code)
                    if let now = tools.zips.first(where: { $0.code == code }), now.visible { zipAdded(Self.rect(now)) }
                } label: {
                    Text(code).font(.system(size: 15, weight: .bold)).foregroundStyle(c)
                        .padding(.leading, 14).padding(.trailing, 6).frame(height: 40)
                }
                Button { tools.removeZip(code) } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(c)
                        .frame(width: 34, height: 40)
                }
                .accessibilityLabel("Remove \(code)")
            }
            .buttonStyle(.plain)
            .background(c.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(c.opacity(z.visible ? 1 : 0.3)))
            .opacity(z.visible ? 1 : 0.5)
        }
    }

    private func seg(_ title: String, _ b: Basemap) -> some View {
        option(title, on: basemap == b.rawValue) { basemap = b.rawValue }
    }

    private func option(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(on ? .white : Theme.muted)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(on ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(on ? .clear : Theme.border))
        }
        .buttonStyle(.plain)
    }
}

/// Wraps tags onto as many lines as needed.
struct FlowRow<Content: View>: View {
    let items: [String]
    let content: (String) -> Content
    init(_ items: [String], @ViewBuilder content: @escaping (String) -> Content) {
        self.items = items
        self.content = content
    }
    var body: some View {
        FlowLayout(spacing: 8) { ForEach(items, id: \.self) { content($0) } }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, p) in arrange(bounds.width, subviews).points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], width: CGFloat, height: CGFloat) {
        var pts: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            pts.append(CGPoint(x: x, y: y))
            x += s.width + spacing
            rowH = max(rowH, s.height)
            maxW = max(maxW, x - spacing)
        }
        return (pts, maxW, y + rowH)
    }
}

/// The web's Export panel: totals, status filters, a preview and the CSV.
struct ExportSheet: View {
    let pins: PinStore
    @State private var included = Set(PinStatus.allCases)
    @State private var fileURL: URL?

    var body: some View {
        let all = Array(pins.pins.values)
        let rows = all.filter { included.contains($0.status) }.sorted { $0.ts > $1.ts }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Export data").font(.title2.bold()).foregroundStyle(Theme.text)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                    stat("Total pins", all.count, Theme.text)
                    stat("Interested", all.filter { $0.status == .interest }.count, PinStatus.interest.color)
                    stat("Door hangers", all.filter { $0.status == .hanger }.count, PinStatus.hanger.color)
                    stat("Do not return", all.filter { $0.status == .dnr }.count, PinStatus.dnr.color)
                }
                heading("Include statuses")
                FlowLayout(spacing: 8) {
                    ForEach(PinStatus.allCases) { s in toggle(s) }
                }
                heading("Preview (\(rows.count) rows)")
                if rows.isEmpty {
                    Text("No pins match these filters").foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 16)
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(rows.prefix(50)) { previewRow($0) }
                    }
                    if rows.count > 50 {
                        Text("+ \(rows.count - 50) more in the CSV").foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                }
                if let fileURL, !rows.isEmpty {
                    ShareLink(item: fileURL) {
                        Label("Share CSV", systemImage: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: Theme.tapHeight)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radius))
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
        .task(id: "\(included.map(\.rawValue).sorted())-\(pins.version)") { write(rows) }
    }

    private func heading(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
    }

    private func stat(_ label: String, _ v: Int, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(c)
            Text("\(v)").font(.system(size: 26, weight: .bold)).foregroundStyle(c).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func toggle(_ s: PinStatus) -> some View {
        let on = included.contains(s)
        return Button {
            if on { included.remove(s) } else { included.insert(s) }
        } label: {
            HStack(spacing: 8) {
                Circle().fill(s.color).frame(width: 10, height: 10)
                Text(s.label).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 14).frame(height: 42)
            .background(on ? Theme.card : .clear, in: Capsule())
            .overlay(Capsule().stroke(on ? s.color : Theme.border))
            .opacity(on ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func previewRow(_ p: Pin) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(p.addr.isEmpty ? "Unknown" : p.addr).font(.system(size: 15)).foregroundStyle(Theme.text).lineLimit(1)
                Text(p.status.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(p.status.color)
            }
            Spacer()
            if p.ts != 0 {
                Text(PinCSV.previewDate(p.ts)).font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 12).frame(minHeight: 52)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func write(_ rows: [Pin]) {
        let day = ISO8601DateFormatter.string(from: Date(), timeZone: .gmt, formatOptions: [.withFullDate])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("knoxcanvas_\(day).csv")
        do {
            try PinCSV.make(rows).write(to: url, atomically: true, encoding: .utf8)
            fileURL = url
        } catch { fileURL = nil }
    }
}

/// Same columns and formatting as the web's export (keep the column order).
enum PinCSV {
    private static func formatter(_ f: String) -> DateFormatter {
        let d = DateFormatter()
        d.locale = Locale(identifier: "en_US_POSIX")
        d.dateFormat = f
        return d
    }
    private static let csvDate = formatter("MM/dd/yyyy")
    private static let shortDate = formatter("MMM d, yyyy")

    static func previewDate(_ ms: Int64) -> String { shortDate.string(from: Date(timeIntervalSince1970: Double(ms) / 1000)) }

    static func make(_ rows: [Pin]) -> String {
        var lines = ["Address,Status,Date Added,Note,Year Built,Latitude,Longitude"]
        for p in rows {
            let date = p.ts != 0 ? csvDate.string(from: Date(timeIntervalSince1970: Double(p.ts) / 1000)) : ""
            lines.append([p.addr, p.status.label, date, p.note, p.yearBuilt,
                          String(format: "%.6f", p.lat), String(format: "%.6f", p.lng)]
                .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}
