import SwiftUI
import UIKit

// Palette and building blocks copied from getcroc.com: monospace type, square
// corners everywhere, 1px borders, off-black page (#121411) with darker panels (#050605).

private func dynamic(light: UInt32, dark: UInt32) -> Color {
    Color(uiColor: UIColor { traits in
        let hex = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
    })
}

extension Color {
    /// The dark navy of the favicon outline; readable on the accent green.
    static let onAccent = Color(red: 1.0 / 255, green: 20.0 / 255, blue: 60.0 / 255)
    static let canvas = dynamic(light: 0xF2F1EC, dark: 0x121411)
    static let panel = dynamic(light: 0xFFFFFF, dark: 0x050605)
    static let ink = dynamic(light: 0x000000, dark: 0xFFFFFF)
    static let muted = dynamic(light: 0x555555, dark: 0xA4A4A4)
    static let softBorder = dynamic(light: 0xAAAAAA, dark: 0x4B4B4B)
}


/// Bordered, square panel.
struct Panel<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(Color.muted)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.panel)
        .overlay(Rectangle().stroke(Color.ink, lineWidth: 1))
    }
}

/// Square text input.
struct SiteFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(Color.canvas)
            .overlay(Rectangle().stroke(Color.softBorder, lineWidth: 1))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }
}

extension View {
    func siteField() -> some View { modifier(SiteFieldStyle()) }
}

/// Primary action: accent fill with the favicon's navy text, square.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.onAccent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.accentColor.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35))
    }
}

/// Secondary action: bordered, square.
struct OutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color = .ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint.opacity(isEnabled ? 1 : 0.4))
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(configuration.isPressed ? Color.softBorder.opacity(0.4) : Color.clear)
            .overlay(Rectangle().stroke(isEnabled ? Color.ink : Color.softBorder, lineWidth: 1))
    }
}

/// Row of flat tabs; the selected one is inverted, like the website.
struct SiteTabs<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    var symbol: ((Item) -> String)?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                let selected = item == selection
                Button { selection = item } label: {
                    HStack(spacing: 6) {
                        if let symbol { Image(systemName: symbol(item)) }
                        Text(title(item))
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundStyle(selected ? Color.panel : Color.muted)
                    .background(selected ? Color.ink : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .background(Color.panel)
        .overlay(Rectangle().stroke(Color.ink, lineWidth: 1))
    }
}

/// Square checkbox row (the system switch is round).
struct SiteCheckbox: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 12) {
                ZStack {
                    Rectangle().stroke(Color.ink, lineWidth: 1)
                    if isOn {
                        Rectangle().fill(Color.accentColor).padding(3)
                    }
                }
                .frame(width: 22, height: 22)
                Text(title).foregroundStyle(Color.ink)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}
