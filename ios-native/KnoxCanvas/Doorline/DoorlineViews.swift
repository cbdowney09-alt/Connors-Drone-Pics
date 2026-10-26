import SwiftUI
import MapKit

private let routeColor = Color(hex: 0x06b6d4)

private func heading(_ t: String) -> some View {
    Text(t.uppercased()).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
}

private func hungAt(_ p: Pin) -> Int64 {
    let n = (p.raw["hangerAt"] as? NSNumber)?.int64Value ?? 0
    return n != 0 ? n : p.ts
}

/// One route with its hanger count. Tapping it shows it on the map.
private struct RouteRow: View {
    let area: DoorlineStore.Area
    let count: Int
    var remove: (() -> Void)?
    let show: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4).fill(routeColor).frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(area.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                Text("\(area.isZip ? "Zip code" : "Neighborhood") \u{00B7} \(count) hung")
                    .font(.system(size: 14)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if let remove {
                Button("Remove", action: remove)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.error)
                    .frame(minWidth: 44, minHeight: 44)
            } else {
                Text("\(count)").font(.system(size: 20, weight: .heavy)).monospacedDigit().foregroundStyle(PinStatus.hanger.color)
            }
        }
        .padding(.horizontal, 14).frame(minHeight: 62)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        .contentShape(Rectangle())
        .onTapGesture(perform: show)
    }
}

/// Doorline client: how many door hangers, where, and the crew's walk paths.
struct HangersSheet: View {
    let pins: PinStore
    let doorline: DoorlineStore
    @Binding var pathsOn: Bool
    var show: (MKMapRect) -> Void
    var toast: (String) -> Void
    @State private var fileURL: URL?

    var body: some View {
        let list = pins.pins.values.filter { $0.status == .hanger }.sorted { hungAt($0) > hungAt($1) }
        let weekAgo = nowMs() - 7 * 86_400_000
        let monthStart = Int64((Calendar.current.dateInterval(of: .month, for: Date())?.start.timeIntervalSince1970 ?? 0) * 1000)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Your door hangers").font(.title2.bold()).foregroundStyle(Theme.text)
                VStack(spacing: 2) {
                    Text("\(list.count)").font(.system(size: 52, weight: .heavy)).monospacedDigit().foregroundStyle(PinStatus.hanger.color)
                    Text("door hangers hung").font(.system(size: 15)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 18)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                HStack(spacing: 8) {
                    stat("\(list.filter { hungAt($0) >= weekAgo }.count)", "Last 7 days")
                    stat("\(list.filter { hungAt($0) >= monthStart }.count)", "This month")
                    stat("\(doorline.areas.count)", "Routes")
                }
                Toggle(isOn: $pathsOn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show walk paths").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                        Text("The streets our crew walked, from their GPS").font(.system(size: 14)).foregroundStyle(Theme.muted)
                    }
                }
                .tint(PinStatus.interest.color)
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))

                heading("By route")
                if doorline.areas.isEmpty {
                    Text("No routes yet. Add zip codes or neighborhoods under Routes.")
                        .foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                ForEach(doorline.areas) { a in
                    RouteRow(area: a, count: doorline.count(a, in: list)) {
                        if let r = doorline.bounds(a) { show(r) } else { toast("Still loading that boundary") }
                    }
                }

                heading("Most recent")
                if list.isEmpty {
                    Text("No door hangers yet").foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 12)
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(list.prefix(25)) { p in
                            HStack {
                                Text(p.addr.isEmpty ? "Address loading" : p.addr).font(.system(size: 15)).foregroundStyle(Theme.text).lineLimit(1)
                                Spacer()
                                Text(PinCSV.previewDate(hungAt(p))).font(.system(size: 13)).foregroundStyle(Theme.muted)
                            }
                            .padding(.horizontal, 12).frame(minHeight: 48)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    if list.count > 25 {
                        Text("+ \(list.count - 25) more in the CSV").foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
                    }
                }
                if let fileURL, !list.isEmpty {
                    ShareLink(item: fileURL) {
                        Label("Share addresses (CSV)", systemImage: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: Theme.tapHeight)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radius))
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
        .task(id: pins.version) { write(list) }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 24, weight: .heavy)).monospacedDigit().foregroundStyle(Theme.text)
            Text(l.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    /// Same columns as every other export; the date is when the hanger was left. Notes are the
    /// crew's own, so they stay out.
    private func write(_ rows: [Pin]) {
        let day = ISO8601DateFormatter.string(from: Date(), timeZone: .gmt, formatOptions: [.withFullDate])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("door_hangers_\(day).csv")
        let clean = rows.map { p -> Pin in
            var q = p
            q.note = ""
            q.ts = hungAt(p)
            return q
        }
        do {
            try PinCSV.make(clean).write(to: url, atomically: true, encoding: .utf8)
            fileURL = url
        } catch { fileURL = nil }
    }
}

/// Doorline client: the zip codes and neighborhoods they want hung.
struct RoutesSheet: View {
    let pins: PinStore
    let doorline: DoorlineStore
    var draw: () -> Void
    var show: (MKMapRect) -> Void
    var toast: (String) -> Void
    @State private var zip = ""
    @State private var confirm: DoorlineStore.Area?
    @FocusState private var zipFocused: Bool

    var body: some View {
        let hung = pins.pins.values.filter { $0.status == .hanger }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Routes").font(.title2.bold()).foregroundStyle(Theme.text)
                Text("Pick the zip codes and neighborhoods you want hung. Doorline Hangers sees them right away.")
                    .font(.system(size: 15)).foregroundStyle(Theme.muted)
                heading("Add a zip code")
                HStack(spacing: 8) {
                    TextField("", text: $zip, prompt: Text("Zip code, e.g. 37923").foregroundStyle(Theme.muted))
                        .keyboardType(.numberPad)
                        .focused($zipFocused)
                        .font(.system(size: 17)).foregroundStyle(Theme.text)
                        .padding(.horizontal, 14).frame(height: Theme.tapHeight)
                        .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.radius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.border))
                        .onChange(of: zip) { _, v in
                            let d = String(v.filter(\.isNumber).prefix(5))
                            if d != v { zip = d }
                        }
                    Button {
                        zipFocused = false
                        let z = zip
                        zip = ""
                        Task { toast(await doorline.addZip(z)) }
                    } label: {
                        Group {
                            if doorline.loadingZip != nil { ProgressView().tint(.white) } else { Text("Add") }
                        }
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 84, height: Theme.tapHeight)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radius))
                    }
                    .buttonStyle(.plain)
                    .disabled(doorline.loadingZip != nil)
                }
                KnoxButton(title: "Draw a neighborhood on the map", style: .ghost, action: draw)
                heading("Your routes")
                if doorline.areas.isEmpty {
                    Text("No routes yet. Add a zip code or draw a neighborhood.")
                        .foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                ForEach(doorline.areas) { a in
                    RouteRow(area: a, count: doorline.count(a, in: Array(hung)), remove: { confirm = a }) {
                        if let r = doorline.bounds(a) { show(r) } else { toast("Still loading that boundary") }
                    }
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.bg)
        .confirmationDialog("Remove \(confirm?.name ?? "") from your routes?",
                            isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible, presenting: confirm) { a in
            Button("Remove", role: .destructive) { doorline.remove(a.id) }
        }
    }
}

/// Shift panel: which Doorline clients you're hanging for. Pick one or several; every door you
/// mark goes on each one's map. Locked while clocked in.
struct HangingForPicker: View {
    @Environment(SessionStore.self) private var session
    let clockedIn: Bool

    var body: some View {
        let home = session.companyId ?? ""
        VStack(alignment: .leading, spacing: 8) {
            heading("Hanging for")
            FlowLayout(spacing: 8) {
                if !session.isCrewOnly {
                    chip(session.company?.name ?? "My company", id: home, on: session.workIds.isEmpty)
                }
                ForEach(session.crewJobs, id: \.id) { j in
                    let suffix = j.company.status == .active ? "" : " (\(j.company.status.rawValue))"
                    chip(j.company.name + suffix, id: j.id, on: session.workIds.contains(j.id))
                }
            }
            Text(clockedIn ? "Clock out to switch businesses."
                 : session.workIds.count > 1 ? "Every house you mark goes on all \(session.workIds.count) businesses\u{2019} maps."
                 : "Tap more than one business if you\u{2019}re carrying hangers for several. Every house you mark goes on each one\u{2019}s map.")
                .font(.system(size: 14)).foregroundStyle(Theme.muted)
        }
    }

    private func chip(_ title: String, id: String, on: Bool) -> some View {
        Button { session.toggleWork(id) } label: {
            Text((on && id != session.companyId ? "\u{2713} " : "") + title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(on ? .white : Theme.muted)
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background(on ? Theme.accent : Theme.card, in: Capsule())
                .overlay(Capsule().stroke(on ? .clear : Theme.border))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(clockedIn && !on)
        .opacity(clockedIn && !on ? 0.45 : 1)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
