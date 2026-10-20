import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}

/// Colors match the web app's dark theme.
enum Theme {
    static let bg = Color(hex: 0x0f1117)
    static let card = Color(hex: 0x1a1d27)
    static let field = Color(hex: 0x252836)
    static let border = Color(hex: 0x2e3244)
    static let accent = Color(hex: 0x4f6ef7)
    static let text = Color.white
    static let muted = Color(hex: 0x9ca3af)
    static let error = Color(hex: 0xf87171)
    static let info = Color(hex: 0x34d399)

    static let tapHeight: CGFloat = 54
    static let radius: CGFloat = 12
}

/// Pin statuses. Keys are stored in Firestore; never rename them.
enum PinStatus: String, CaseIterable, Identifiable {
    case none, hanger, interest, no, dnr
    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "Not visited"
        case .hanger: "Door hanger"
        case .interest: "Interested"
        case .no: "Not interested"
        case .dnr: "Do not return"
        }
    }

    var color: Color {
        switch self {
        case .none: Color(hex: 0x6b7280)
        case .hanger: Color(hex: 0xf59e0b)
        case .interest: Color(hex: 0x10b981)
        case .no: Color(hex: 0xef4444)
        case .dnr: Color(hex: 0x7c3aed)
        }
    }
}
