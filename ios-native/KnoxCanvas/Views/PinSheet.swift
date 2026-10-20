import SwiftUI

/// The bottom sheet for one pin, like the web's #sheet.
struct PinSheet: View {
    let store: PinStore
    let pinId: String
    var toast: (String) -> Void
    var close: () -> Void

    @State private var note = ""
    @State private var year = ""
    @State private var noteSave: Task<Void, Never>?
    @State private var yearSave: Task<Void, Never>?
    @State private var confirmDelete = false
    @FocusState private var focus: Field?
    @Environment(\.openURL) private var openURL

    enum Field { case note, year }

    private var pin: Pin? { store.pins[pinId] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let pin {
                    header(pin)
                    ForEach(PinStatus.allCases) { s in statusButton(s, active: pin.status == s) }
                    details
                    actions
                } else {
                    Text("This pin was removed.").foregroundStyle(Theme.muted).padding(.top, 30)
                    KnoxButton(title: "Done", style: .ghost, action: close)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.bg)
        .onAppear {
            note = pin?.note ?? ""
            year = pin?.yearBuilt ?? ""
        }
        .onDisappear(perform: flush)
        .confirmationDialog("Remove this pin?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove pin", role: .destructive) {
                noteSave?.cancel(); yearSave?.cancel()
                store.delete(pinId)
                toast("Pin removed")
                close()
            }
        }
    }

    private func header(_ p: Pin) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(p.addr.isEmpty ? "Unnamed location" : p.addr)
                .font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(format: "%.5f, %.5f", p.lat, p.lng) + (year.isEmpty ? "" : " \u{00B7} Built \(year)"))
                .font(.system(size: 14)).foregroundStyle(Theme.muted)
            Button {
                if let url = zillowURL(p.addr) { openURL(url) }
            } label: {
                Label("View on Zillow", systemImage: "arrow.up.right.square")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(minHeight: 40)
            }
            .foregroundStyle(Theme.accent)
        }
        .padding(.bottom, 4)
    }

    private func statusButton(_ s: PinStatus, active: Bool) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            store.setStatus(pinId, s)
            toast("Saved: \(s.label)")
        } label: {
            HStack(spacing: 14) {
                Circle().fill(s.color).frame(width: 18, height: 18)
                Text(s.sheetLabel).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if active { Image(systemName: "checkmark").font(.system(size: 17, weight: .bold)).foregroundStyle(s.color) }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: Theme.tapHeight)
            .background(active ? s.color.opacity(0.18) : Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(active ? s.color : Theme.border, lineWidth: active ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var details: some View {
        VStack(spacing: 10) {
            TextField("", text: $note, prompt: Text("Add a note (optional)\u{2026}").foregroundStyle(Theme.muted), axis: .vertical)
                .lineLimit(2...5)
                .focused($focus, equals: .note)
                .font(.system(size: 17)).foregroundStyle(Theme.text)
                .padding(14)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.radius))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.border))
                .onChange(of: note) { _, v in
                    guard focus == .note else { return }
                    noteSave?.cancel()
                    noteSave = debounced { store.setNote(pinId, v) }
                }

            HStack(spacing: 10) {
                TextField("", text: $year, prompt: Text("Year built").foregroundStyle(Theme.muted))
                    .keyboardType(.numberPad)
                    .focused($focus, equals: .year)
                    .font(.system(size: 17)).foregroundStyle(Theme.text)
                    .padding(.horizontal, 14)
                    .frame(width: 130, height: Theme.tapHeight)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.radius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.border))
                    .onChange(of: year) { _, v in
                        let digits = String(v.filter(\.isNumber).prefix(4))
                        if digits != v { year = digits; return }
                        guard focus == .year else { return }
                        yearSave?.cancel()
                        yearSave = debounced { store.setYear(pinId, digits) }
                    }
                Button(action: applyYear) {
                    Text("Apply to nearby pins (400 m)")
                        .font(.system(size: 15, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: Theme.tapHeight)
                        .foregroundStyle(Theme.text)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.border))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            KnoxButton(title: "\u{1F4CD} Set as route start", style: .ghost) {
                guard let p = pin else { return }
                store.routeStart = (p.coordinate, p.addr.isEmpty ? "Selected pin" : p.addr)
                toast("Route start set")
                close()
            }
            Button { confirmDelete = true } label: {
                Text("Remove this pin")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.error)
                    .frame(maxWidth: .infinity, minHeight: Theme.tapHeight)
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.error.opacity(0.5)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            KnoxButton(title: "Done", action: close)
        }
        .padding(.top, 6)
    }

    private func applyYear() {
        focus = nil
        guard !year.isEmpty else { toast("Enter a year first"); return }
        yearSave?.cancel()
        let n = store.applyYearNearby(pinId, year: year)
        toast("Applied \(year) to \(n) pins")
    }

    private func debounced(_ work: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            if !Task.isCancelled { work() }
        }
    }

    /// Saves anything still waiting on the debounce when the sheet closes.
    private func flush() {
        guard let p = store.pins[pinId] else { return }
        if noteSave != nil, note != p.note { noteSave?.cancel(); store.setNote(pinId, note) }
        if yearSave != nil, year != p.yearBuilt { yearSave?.cancel(); store.setYear(pinId, year) }
    }

    private func zillowURL(_ addr: String) -> URL? {
        let a = addr.trimmingCharacters(in: .whitespaces)
        // Same as encodeURIComponent: escape everything but unreserved characters.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        return URL(string: "https://www.zillow.com/homes/\(a.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")_rb/")
    }
}

extension PinStatus {
    /// The longer wording used on the sheet's buttons.
    var sheetLabel: String {
        switch self {
        case .none: "Not visited"
        case .hanger: "Door hanger left"
        case .interest: "Spoke to someone \u{2014} interested"
        case .no: "Spoke to someone \u{2014} not interested"
        case .dnr: "Do not return / skip"
        }
    }
}
