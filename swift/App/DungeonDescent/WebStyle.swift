import SwiftUI
import UIKit

// The web version's look: its color tokens (:root in index.html), its three
// Google fonts and its button styles, so the Swift screens match it.

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}

enum Theme {
    // :root
    static let bgVoid = Color(hex: 0x080604)
    static let bgDeep = Color(hex: 0x0e0b08)
    static let bgStone = Color(hex: 0x1a1410)
    static let bgPanel = Color(hex: 0x1f1812)
    static let gold = Color(hex: 0xc9a227)
    static let goldBright = Color(hex: 0xf0c040)
    static let goldDim = Color(hex: 0x7a6018)
    static let blood = Color(hex: 0x8b1a1a)
    static let bloodBright = Color(hex: 0xc0392b)
    static let ash = Color(hex: 0x9e8e78)
    static let ashLight = Color(hex: 0xd4c4aa)
    static let textPrimary = Color(hex: 0xe8d9c0)
    static let textSecondary = Color(hex: 0xa89070)
    static let textDim = Color(hex: 0x5a4e40)
    static let borderDim = Color(hex: 0x2e2418)
    static let borderGlow = Color(hex: 0x6a5010)
    static let panel = bgPanel

    // 1rem in the web version is 16 points. Fonts scale with Dynamic Type.
    static func cinzel(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Cinzel", size: size, relativeTo: style).weight(weight)
    }
    static func decorative(_ size: CGFloat, black: Bool = false, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom(black ? "CinzelDecorative-Black" : "CinzelDecorative-Bold", size: size, relativeTo: style)
    }
    static func crimson(_ size: CGFloat = 16, italic: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(italic ? "CrimsonText-Italic" : "CrimsonText-Regular", size: size, relativeTo: style)
    }
}

/// .menu-btn and .menu-btn.primary
struct MenuButtonStyle: ButtonStyle {
    var primary = false
    /// The buttons the web version colors with an inline style.
    var color: Color? = nil
    var border: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        configuration.label
            .font(Theme.cinzel(14, weight: primary ? .bold : .regular))
            .tracking(1.7)
            .textCase(.uppercase)
            .foregroundStyle(down ? Theme.goldBright : primary ? Theme.gold : color ?? Color(hex: 0xb0a080))
            .multilineTextAlignment(.center)
            .padding(.vertical, 9)
            .padding(.horizontal, 20)
            .frame(maxWidth: 260, minHeight: 44)
            .background(down ? (primary ? Color(hex: 0x1e1800) : Color(hex: 0x1a1508))
                        : primary ? Color(hex: 0x100e00) : Color(hex: 0x0d0d0d))
            .overlay(RoundedRectangle(cornerRadius: 2)
                .stroke(down ? (primary ? Theme.goldBright : Color(hex: 0x6a5020))
                        : primary ? Color(hex: 0xcc9944) : border ?? Color(hex: 0x2a2218), lineWidth: 1))
            .scaleEffect(down ? 1.03 : 1)
            .animation(.easeOut(duration: 0.15), value: down)
    }
}

/// .back-btn
struct BackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.cinzel(10.4))
            .tracking(2)
            .textCase(.uppercase)
            .foregroundStyle(configuration.isPressed ? Theme.ash : Theme.textDim)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .overlay(Rectangle().stroke(configuration.isPressed ? Theme.goldDim : Theme.borderDim, lineWidth: 1))
    }
}

/// .menu-sep
struct MenuSeparator: View {
    var body: some View {
        Rectangle().fill(Theme.borderDim).frame(width: 80, height: 1).padding(.vertical, 6)
            .accessibilityHidden(true)
    }
}

/// .ornament: line, dot, glowing diamond, dot, line.
struct Ornament: View {
    var body: some View {
        HStack(spacing: 10) {
            LinearGradient(colors: [.clear, Theme.borderGlow], startPoint: .leading, endPoint: .trailing)
                .frame(width: 80, height: 1)
            Rectangle().fill(Theme.goldDim).frame(width: 4, height: 4).rotationEffect(.degrees(45))
            Rectangle().fill(Theme.gold).frame(width: 10, height: 10).rotationEffect(.degrees(45))
                .shadow(color: Theme.gold.opacity(0.7), radius: 4)
            Rectangle().fill(Theme.goldDim).frame(width: 4, height: 4).rotationEffect(.degrees(45))
            LinearGradient(colors: [Theme.borderGlow, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 80, height: 1)
        }
        .padding(.vertical, 12)
        .accessibilityHidden(true)
    }
}

/// The page background every screen sits on (body, .bg-radial and .vignette).
struct WebBackground: View {
    var body: some View {
        ZStack {
            Theme.bgVoid
            RadialGradient(colors: [Theme.blood.opacity(0.07), .clear], center: .bottom, startRadius: 0, endRadius: 500)
            RadialGradient(colors: [.clear, .black.opacity(0.75)], center: .center, startRadius: 150, endRadius: 700)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// .screen-header: back button(s) and the screen title, then .screen-subtitle.
struct ScreenHeader<Extra: View>: View {
    @EnvironmentObject var router: Router
    let title: String
    var subtitle: String? = nil
    var backLabel = "← Menu"
    var backHint = "Back to main menu"
    var back: Router.Screen = .menu
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(backLabel) { router.goTo(back) }
                    .buttonStyle(BackButtonStyle())
                    .accessibilityLabel(backHint)
                extra()
            }
            Text(title)
                .font(Theme.decorative(20))
                .foregroundStyle(Theme.gold)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.crimson(14.4, italic: true))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension ScreenHeader where Extra == EmptyView {
    init(title: String, subtitle: String? = nil, backLabel: String = "← Menu",
         backHint: String = "Back to main menu", back: Router.Screen = .menu) {
        self.init(title: title, subtitle: subtitle, backLabel: backLabel, backHint: backHint, back: back) { EmptyView() }
    }
}

/// A web-styled screen: background, scrolling column and header.
struct WebScreen<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            WebBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) { content() }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 60)
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(Theme.textPrimary)
        .font(Theme.crimson())
    }
}

/// .btn-gold, .btn-ghost and .btn-red
struct WebButtonStyle: ButtonStyle {
    enum Kind { case gold, ghost, red }
    var kind: Kind = .ghost

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        configuration.label
            .font(Theme.cinzel(11.5, weight: kind == .gold ? .bold : .regular))
            .tracking(2.3)
            .textCase(.uppercase)
            .foregroundStyle(kind == .gold ? Theme.bgVoid
                             : kind == .red ? (down ? Theme.textPrimary : Theme.bloodBright)
                             : (down ? Theme.textPrimary : Theme.ash))
            .padding(.vertical, 11)
            .padding(.horizontal, kind == .gold ? 26 : 22)
            .frame(minHeight: 44)
            .background(kind == .gold ? (down ? Theme.goldBright : Theme.gold)
                        : kind == .red && down ? Theme.blood : Color.clear)
            .overlay(Rectangle().stroke(kind == .gold ? .clear
                                        : kind == .red ? Theme.blood
                                        : (down ? Theme.ash : Theme.borderDim), lineWidth: 1))
    }
}

/// .overlay with an .ov-box: a dimmed page and a centered dialog that
/// VoiceOver keeps focus inside, like aria-modal.
struct WebOverlay<Content: View>: View {
    var danger = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(spacing: 20) { content() }
                .multilineTextAlignment(.center)
                .padding(32)
                .frame(maxWidth: 360)
                .background(Color(hex: 0x130f0a))
                .overlay(Rectangle().stroke(danger ? Theme.blood : Theme.borderDim, lineWidth: 1))
                .overlay(alignment: .top) {
                    if danger { Rectangle().fill(Theme.bloodBright).frame(height: 2) }
                }
                .shadow(color: .black.opacity(0.9), radius: 30)
                .padding(.horizontal, 18)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity)
    }
}

/// .ov-title and .ov-text
struct OverlayTitle: View {
    let text: String
    var red = false
    var body: some View {
        Text(text).font(Theme.decorative(17.6))
            .foregroundStyle(red ? Theme.bloodBright : Theme.gold)
            .accessibilityAddTraits(.isHeader)
    }
}

struct OverlayText: View {
    let text: String
    var body: some View {
        Text(text).font(Theme.crimson(14.4, italic: true)).foregroundStyle(Theme.ash).lineSpacing(4)
    }
}
