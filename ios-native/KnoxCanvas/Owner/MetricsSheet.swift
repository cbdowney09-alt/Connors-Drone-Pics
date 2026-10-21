import SwiftUI

/// The web's "Team metrics" panel: time range, employee picker, summary cards,
/// per-employee breakdown and recent shifts.
struct MetricsSheet: View {
    let pins: PinStore
    @State private var team: TeamStore
    @State private var range = Metrics.Range.today
    @State private var who: String?

    init(pins: PinStore, companyId: String, uid: String) {
        self.pins = pins
        _team = State(initialValue: TeamStore(companyId: companyId, uid: uid))
    }

    var body: some View {
        let m = Metrics(pins: Array(pins.pins.values), shifts: team.shifts, members: team.members,
                        since: range.since(), who: who)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Team metrics").font(.title2.bold()).foregroundStyle(Theme.text)
                    Spacer()
                    Button { Task { await team.loadMetrics() } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold)).frame(minHeight: 44)
                    }
                    .foregroundStyle(Theme.accent)
                    .disabled(team.loading)
                }

                chipRow {
                    ForEach(Metrics.Range.allCases) { r in
                        PickChip(label: r.label, active: range == r) { range = r }
                    }
                }
                chipRow {
                    PickChip(label: "Everyone", active: who == nil) { who = nil }
                    ForEach(team.members) { e in
                        PickChip(label: e.display, active: who == e.uid) { who = e.uid }
                    }
                }

                if let err = team.loadError {
                    Text(err).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 20)
                } else if team.loading && team.members.isEmpty {
                    ProgressView().tint(Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 30)
                } else {
                    summary(m)
                    if who == nil {
                        section("Employee breakdown")
                        if m.breakdown.isEmpty { empty("No team data yet") }
                        ForEach(m.breakdown) { breakdownRow($0) }
                    }
                    section("Recent shifts")
                    if m.shifts.isEmpty { empty("No shifts in this period") }
                    ForEach(m.shifts.prefix(20)) { shiftRow($0) }
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
        .task { await team.loadMetrics() }
    }

    private func chipRow<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) { content() }
        }
    }

    private func section(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted).padding(.top, 6)
    }

    private func empty(_ t: String) -> some View {
        Text(t).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 16)
    }

    // MARK: Cards

    private func summary(_ m: Metrics) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            card("\(m.hangers)", "Hangers", PinStatus.hanger.color)
            card("\(m.interested)", "Interested", PinStatus.interest.color)
            card(m.perHour, "Hangers/hr")
            card(m.hoursText, "Hours")
            card("\(m.shifts.count)", "Shifts")
            card(m.perShift, "Per shift")
        }
    }

    private func card(_ value: String, _ label: String, _ color: Color = Theme.text) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
    }

    private func breakdownRow(_ r: Metrics.EmployeeRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(r.member.display).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
            HStack(spacing: 8) {
                mini("\(r.hangers)", "Hangers", highlight: true)
                mini(r.hours > 0 ? String(format: "%.1f", Double(r.hangers) / r.hours) : "\u{2014}", "Per hour")
                mini(String(format: "%.1fh", r.hours), "Hours")
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
    }

    private func mini(_ v: String, _ l: String, highlight: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 19, weight: .bold)).monospacedDigit()
                .foregroundStyle(highlight ? PinStatus.hanger.color : Theme.text)
            Text(l).font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 10))
    }

    private func shiftRow(_ s: Shift) -> some View {
        let name = team.members.first { $0.uid == s.userId }?.display
            ?? (s.userName.isEmpty ? "Former member" : s.userName)
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                Text("\(Self.day(s.clockIn)) \u{00B7} \(ShiftFormat.duration(s.durationMs))")
                    .font(.system(size: 14)).foregroundStyle(Theme.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(s.hangers)").font(.system(size: 20, weight: .bold)).foregroundStyle(PinStatus.hanger.color)
                Text("\(ShiftStore.perHourText(s.hangersPerHour))/hr").font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
    }

    private static let dayF: DateFormatter = {
        let d = DateFormatter()
        d.locale = Locale(identifier: "en_US_POSIX")
        d.dateFormat = "EEE, MMM d"
        return d
    }()
    private static func day(_ ms: Int64) -> String { dayF.string(from: Date(timeIntervalSince1970: Double(ms) / 1000)) }
}

private struct PickChip: View {
    let label: String
    let active: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? .white : Theme.text)
                .padding(.horizontal, 15).frame(height: 40)
                .background(active ? Theme.accent : Theme.card, in: Capsule())
                .overlay(Capsule().stroke(active ? .clear : Theme.border))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
