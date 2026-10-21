import SwiftUI

struct Logo: View {
    var body: some View {
        (Text("Knox").foregroundStyle(Theme.text) + Text("Canvas").foregroundStyle(Theme.accent))
            .font(.system(size: 34, weight: .heavy))
    }
}

struct KnoxField: View {
    let placeholder: String
    @Binding var text: String
    var secure = false
    var content: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    var onSubmit: () -> Void = {}

    var body: some View {
        Group {
            if secure {
                SecureField("", text: $text, prompt: prompt)
            } else {
                TextField("", text: $text, prompt: prompt)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(capitalization)
                    .autocorrectionDisabled()
            }
        }
        .textContentType(content)
        .onSubmit(onSubmit)
        .font(.system(size: 17))
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 16)
        .frame(height: Theme.tapHeight)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.border))
    }

    private var prompt: Text { Text(placeholder).foregroundStyle(Theme.muted) }
}

struct KnoxButton: View {
    enum Style { case primary, ghost, google }
    let title: String
    var busyTitle: String?
    var style: Style = .primary
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if busy { ProgressView().tint(style == .google ? .black : .white) }
                else if style == .google { GoogleG() }
                Text(busy ? (busyTitle ?? title) : title).font(.system(size: 17, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: Theme.tapHeight)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(style == .ghost ? Theme.border : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.75 : 1)
    }

    private var foreground: Color { style == .google ? .black : .white }
    private var background: Color {
        switch style {
        case .primary: Theme.accent
        case .ghost: .clear
        case .google: .white
        }
    }
}

/// Google's multicolor "G", drawn so no image asset is needed.
struct GoogleG: View {
    var body: some View {
        ZStack {
            Circle().trim(from: 0.0, to: 0.25).stroke(Color(hex: 0x4285F4), lineWidth: 3.5).rotationEffect(.degrees(-10))
            Circle().trim(from: 0.25, to: 0.5).stroke(Color(hex: 0x34A853), lineWidth: 3.5).rotationEffect(.degrees(-10))
            Circle().trim(from: 0.5, to: 0.62).stroke(Color(hex: 0xFBBC05), lineWidth: 3.5).rotationEffect(.degrees(-10))
            Circle().trim(from: 0.62, to: 0.9).stroke(Color(hex: 0xEA4335), lineWidth: 3.5).rotationEffect(.degrees(-10))
            Rectangle().fill(Color(hex: 0x4285F4)).frame(width: 8, height: 3.5).offset(x: 4)
        }
        .frame(width: 16, height: 16)
    }
}

struct MessageText: View {
    let error: String
    let info: String
    var body: some View {
        if !error.isEmpty {
            Text(error).font(.system(size: 15)).foregroundStyle(Theme.error).frame(maxWidth: .infinity, alignment: .leading)
        } else if !info.isEmpty {
            Text(info).font(.system(size: 15)).foregroundStyle(Theme.info).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(20)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.border))
    }
}

struct LinkButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(title, action: action)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(minHeight: 44)
    }
}

struct Toast: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().stroke(Theme.border))
            .shadow(radius: 8)
    }
}
