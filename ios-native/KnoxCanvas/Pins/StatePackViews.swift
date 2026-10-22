import SwiftUI

/// Account → House data: which states are on this phone, download more, update or remove.
struct HouseDataSheet: View {
    let companyStates: [String]
    @State private var packs = StatePacks.shared
    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("House data").font(.title2.bold()).foregroundStyle(Theme.text)
                Text("Houses for routes and house detection, stored on this phone so they work with no signal. Download each state you work in.")
                    .font(.system(size: 14)).foregroundStyle(Theme.muted)

                if packs.available.isEmpty {
                    if packs.manifestError {
                        Text("Couldn\u{2019}t load the list of states. Connect to the internet and try again.")
                            .foregroundStyle(Theme.muted).padding(.vertical, 12)
                        LinkButton(title: "Try again") { Task { await packs.loadManifest() } }
                    } else {
                        ProgressView().tint(Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 30)
                    }
                } else {
                    let mine = packs.available.filter { packs.installed[$0.code] != nil || packs.progress[$0.code] != nil }
                    if !mine.isEmpty {
                        heading("On this phone")
                        ForEach(mine) { row($0) }
                    }
                    heading("All states")
                    KnoxField(placeholder: "Search states", text: $query, capitalization: .words)
                    ForEach(packs.available.filter { packs.installed[$0.code] == nil && packs.progress[$0.code] == nil && matches($0) }) { row($0) }
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
        .scrollDismissesKeyboard(.interactively)
        .task { await packs.loadManifest() }
    }

    private func matches(_ i: StatePacks.Info) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || i.name.lowercased().contains(q) || i.code.lowercased() == q
    }

    private func heading(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted).padding(.top, 8)
    }

    private func row(_ i: StatePacks.Info) -> some View {
        let installed = packs.installed[i.code] != nil
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(i.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                    if companyStates.contains(i.code) {
                        Text("Company").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.15), in: Capsule())
                    }
                }
                if let p = packs.progress[i.code] {
                    ProgressView(value: p).tint(Theme.accent)
                    Text("Downloading\u{2026} \(Int(p * 100))%").font(.system(size: 13)).foregroundStyle(Theme.muted)
                } else {
                    Text("\(Self.mb(installed ? packs.bytesOnDisk(i.code) : i.bytes)) \u{00B7} \(i.houses.formatted()) houses"
                         + (packs.failed.contains(i.code) ? " \u{00B7} download failed" : ""))
                        .font(.system(size: 13)).foregroundStyle(packs.failed.contains(i.code) ? Theme.error : Theme.muted)
                }
            }
            Spacer()
            if packs.progress[i.code] == nil {
                if installed && packs.hasUpdate(i.code) {
                    small("Update", Theme.accent) { packs.download(i.code) }
                } else if installed {
                    small("Remove", Theme.field) { packs.remove(i.code) }
                } else {
                    small(packs.failed.contains(i.code) ? "Retry" : "Download", Theme.accent) { packs.download(i.code) }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(minHeight: 60)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func small(_ t: String, _ bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 14).frame(minHeight: 40)
                .background(bg, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    static func mb(_ bytes: Int) -> String {
        bytes < 1_000_000 ? "<1 MB" : "\(Int((Double(bytes) / 1_000_000).rounded())) MB"
    }
}

/// Owner: pick the states the company works in. Every phone on the team downloads them.
struct CompanyStatesSheet: View {
    let initial: [String]
    var title = "Where does your company work?"
    var save: ([String]) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []
    @State private var query = ""
    @State private var saving = false
    @State private var error = ""

    private var all: [(code: String, name: String)] {
        StatePacks.names.map { ($0.key, $0.value) }.sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.bold()).foregroundStyle(Theme.text)
            Text("Pick every state your crews knock in. Each phone on your team downloads these states\u{2019} houses automatically, so routes and house detection work there.")
                .font(.system(size: 14)).foregroundStyle(Theme.muted)
            KnoxField(placeholder: "Search states", text: $query, capitalization: .words)
            ScrollView {
                LazyVStack(spacing: 6) {
                    let chosen = all.filter { picked.contains($0.code) }
                    let rest = all.filter { !picked.contains($0.code) && matches($0.name, $0.code) }
                    ForEach(chosen + rest, id: \.code) { s in
                        Button {
                            if picked.contains(s.code) { picked.remove(s.code) } else { picked.insert(s.code) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: picked.contains(s.code) ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 22)).foregroundStyle(picked.contains(s.code) ? Theme.accent : Theme.muted)
                                Text(s.name).font(.system(size: 16)).foregroundStyle(Theme.text)
                                Spacer()
                            }
                            .padding(.horizontal, 14).frame(minHeight: 48)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            MessageText(error: error, info: "")
            KnoxButton(title: picked.isEmpty ? "Pick at least one state" : "Save \(picked.count) state\(picked.count == 1 ? "" : "s")",
                       busyTitle: "Saving\u{2026}", busy: saving) {
                guard !picked.isEmpty else { return }
                saving = true
                Task {
                    defer { saving = false }
                    do { try await save(picked.sorted()); dismiss() } catch { self.error = error.localizedDescription }
                }
            }
        }
        .padding(20)
        .background(Theme.bg)
        .scrollDismissesKeyboard(.interactively)
        .task {
            picked = Set(initial)
            if picked.isEmpty, let here = await StatePacks.currentState() { picked.insert(here) }
        }
    }

    private func matches(_ name: String, _ code: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || name.lowercased().contains(q) || code.lowercased() == q
    }
}
