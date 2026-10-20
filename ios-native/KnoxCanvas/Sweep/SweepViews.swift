import SwiftUI

/// "🏠 N houses passed · Street" → Mark N as hangers / Review / ✕ (the web's #sweep-banner).
struct SweepBanner: View {
    let sweep: SweepTracker
    var review: () -> Void

    var body: some View {
        let on = sweep.candidates.filter(\.on).count
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sweep.title).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text).lineLimit(2)
                Text(sweep.subtitle).font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 8) {
                Button { sweep.accept() } label: {
                    Text(on > 0 ? "Mark \(on) as hangers" : "Nothing selected")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(PinStatus.hanger.color, in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(on == 0)
                .opacity(on == 0 ? 0.5 : 1)
                Button(action: review) {
                    Text("Review").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                        .frame(width: 84, height: 50)
                        .background(Theme.field, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                Button { sweep.skip() } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.muted)
                        .frame(width: 50, height: 50)
                        .background(Theme.field, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip these houses")
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(PinStatus.hanger.color.opacity(0.6)))
        .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
        .padding(.horizontal, 12)
    }
}

/// The review list: houses grouped by street, tap to include or leave out.
struct SweepReviewSheet: View {
    let sweep: SweepTracker
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let list = sweep.sortedCandidates
        let on = list.filter(\.on).count
        VStack(spacing: 0) {
            HStack {
                Text("Houses passed").font(.title2.bold()).foregroundStyle(Theme.text)
                Spacer()
                Button(on > 0 ? "None" : "All") { sweep.setAll(on == 0) }
                    .font(.system(size: 16, weight: .semibold)).frame(minHeight: 44)
            }
            .padding(.horizontal, 20).padding(.top, 20)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(list.enumerated()), id: \.element.key) { i, c in
                        let street = c.street.isEmpty ? "Nearby" : c.street
                        if i == 0 || (list[i - 1].street.isEmpty ? "Nearby" : list[i - 1].street) != street {
                            Text(street.uppercased()).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
                                .padding(.top, i == 0 ? 0 : 10)
                        }
                        row(c)
                    }
                }
                .padding(20)
            }

            KnoxButton(title: on > 0 ? "Place \(on) door hanger\(on == 1 ? "" : "s")" : "Skip all") {
                if on > 0 { sweep.accept() } else { sweep.skip() }
                dismiss()
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
        .background(Theme.bg)
        .onChange(of: sweep.candidates.isEmpty) { _, empty in if empty { dismiss() } }
    }

    private func row(_ c: Candidate) -> some View {
        Button { sweep.toggle(c.key) } label: {
            HStack(spacing: 12) {
                Image(systemName: c.on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 24)).foregroundStyle(c.on ? PinStatus.hanger.color : Theme.muted)
                Text(c.addr.isEmpty ? "\(c.num) \(c.street)" : c.addr)
                    .font(.system(size: 16)).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                Spacer()
                if c.dist > 0 { Text("\(c.dist) m").font(.system(size: 13)).foregroundStyle(Theme.muted) }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 54)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
