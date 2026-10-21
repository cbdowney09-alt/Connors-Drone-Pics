import SwiftUI

/// The web's Shifts panel: clock card with a live timer, then shift history and CSV export.
struct ShiftSheet: View {
    let shifts: ShiftStore
    @State private var confirmClockOut = false
    @State private var exportURL: URL?
    @AppStorage("knoxDoorRadius") private var doorRadius = 20.0

    private static let green = PinStatus.interest.color
    private static let red = PinStatus.no.color

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Shifts").font(.title2.bold()).foregroundStyle(Theme.text)
                    Spacer()
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold)).frame(minHeight: 44)
                        }
                        .foregroundStyle(Theme.accent)
                    }
                }
                clockCard
                sweepSetting
                Text("SHIFT HISTORY").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
                if shifts.shifts.isEmpty {
                    Text("No shifts yet").foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    ForEach(shifts.shifts) { ShiftCard(shift: $0) }
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
        .onAppear(perform: writeExport)
        .onChange(of: shifts.shifts.count) { writeExport() }
        .confirmationDialog("Clock out and save this shift?", isPresented: $confirmClockOut, titleVisibility: .visible) {
            Button("Clock out", role: .destructive) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                shifts.clockOut()
            }
        }
    }

    /// How close counts as "walked up to the house" for the street sweep.
    private var sweepSetting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HOUSE DETECTION").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
            Text("While you\u{2019}re clocked in, a house lights up when you get this close to it:")
                .font(.system(size: 14)).foregroundStyle(Theme.muted)
            HStack(spacing: 8) {
                ForEach(SWEEP.doorRadiusChoices, id: \.self) { r in
                    let on = doorRadius == r
                    Button { doorRadius = r } label: {
                        Text("\(Int(r)) m").font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(on ? .white : Theme.muted)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(on ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? .clear : Theme.border))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(doorRadius <= 15 ? "Only when you\u{2019}re right at the house." :
                 doorRadius <= 20 ? "When you walk up to the house (recommended)." :
                 doorRadius <= 30 ? "Also catches houses you pass on the sidewalk." :
                 "Every house along the street, even set back from the road.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
        }
    }

    private var clockCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let start = shifts.clockInTime
            let now = Int64(ctx.date.timeIntervalSince1970 * 1000)
            VStack(spacing: 8) {
                Text(start == nil ? "Clocked out" : "Clocked in")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(start == nil ? Theme.muted : Self.green)
                Text(start.map { ShiftFormat.duration(now - $0) } ?? "00:00:00")
                    .font(.system(size: 48, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(start == nil ? Theme.muted : Theme.text)
                if let start {
                    Text("Since \(ShiftFormat.time(start)) \u{00B7} \(ShiftFormat.date(start))")
                        .font(.system(size: 14)).foregroundStyle(Theme.muted)
                    Text("This shift: \(shifts.hangersSince(start)) hangers")
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(PinStatus.hanger.color)
                }
                Button {
                    if shifts.clockedIn { confirmClockOut = true }
                    else { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); shifts.clockIn() }
                } label: {
                    Text(start == nil ? "Clock in" : "Clock out")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(start == nil ? Self.green : Self.red, in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
        }
    }

    /// The share sheet needs a real file named like the web's download.
    private func writeExport() {
        guard !shifts.shifts.isEmpty else { exportURL = nil; return }
        let day = ISO8601DateFormatter.string(from: Date(), timeZone: .gmt, formatOptions: [.withFullDate])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shifts_\(day).csv")
        do {
            try shifts.csv().write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
        } catch { exportURL = nil }
    }
}

private struct ShiftCard: View {
    let shift: Shift

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(ShiftFormat.date(shift.clockIn)).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Text(ShiftFormat.duration(shift.durationMs)).monospacedDigit()
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            Text("\(ShiftFormat.time(shift.clockIn)) \u{2192} \(ShiftFormat.time(shift.clockOut))")
                .font(.system(size: 14)).foregroundStyle(Theme.muted)
            HStack(spacing: 8) {
                mini("\(shift.hangers)", "Hangers", highlight: true)
                mini(ShiftStore.perHourText(shift.hangersPerHour), "Per hour")
                mini(String(format: "%.2fh", Double(shift.durationMs) / 3_600_000), "Hours")
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border))
    }

    private func mini(_ v: String, _ l: String, highlight: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 20, weight: .bold)).monospacedDigit()
                .foregroundStyle(highlight ? PinStatus.hanger.color : Theme.text)
            Text(l).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 12))
    }
}
