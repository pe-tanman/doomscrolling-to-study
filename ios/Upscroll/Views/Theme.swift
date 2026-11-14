import SwiftUI

/// Upscroll theme, v3 palette. Built in OKLCH (see the values in the comments) so related colours share
/// lightness and chroma: neutrals are near-grey with a faint indigo cast that sits with the lavender→peach art,
/// one deep indigo (藍) is the primary, and the four skill colours have equal lightness so none shouts louder.
/// Every text colour here is ≥ 4.5:1 on white (WCAG AA); see the contrast checks in the commit.
enum Brand {
    // Neutrals (hue ≈ 282–292)
    static let ink = Color(hex: 0x29294D)          // oklch(.30 .065 282) text
    static let ink2 = Color(hex: 0x545571)         // oklch(.46 .045 282) icons, secondary
    static let ink3 = Color(hex: 0x9C9DAE)         // oklch(.70 .025 285) chevrons, inactive
    static let sky = Color(hex: 0xF6F5FC)          // oklch(.972 .010 292) page background
    static let surface = Color.white
    static let mist = Color(hex: 0xF1F0F9)         // oklch(.958 .012 292) wells, chips
    static let line = Color(hex: 0xE3E1ED)         // oklch(.915 .016 292) hairlines, empty tracks
    // Primary: indigo
    static let violet = Color(hex: 0x5D5BC8)       // oklch(.53 .165 280) buttons, tint
    static let violetSoft = Color(hex: 0xEBEBFE)   // oklch(.945 .025 285)
    static let violetDeep = Color(hex: 0x443F9F)   // oklch(.43 .15 280) accent text
    // Accents
    static let sakura = Color(hex: 0xECA1BE)       // oklch(.79 .095 355)
    static let sakuraSoft = Color(hex: 0xFDEAF1)
    static let cream = Color(hex: 0xFEF5E6)        // oklch(.972 .022 80)
    static let sun = Color(hex: 0xF3BE55)          // oklch(.83 .135 82) yamabuki gold, fills only
    static let sunSoft = Color(hex: 0xFEF3D6)
    static let sunDeep = Color(hex: 0x8F5D14)      // oklch(.52 .105 70) gold as text
    // Status
    static let success = Color(hex: 0x0C7D48)      // oklch(.52 .125 155) matcha
    static let successSoft = Color(hex: 0xE1F7E7)
    static let warn = Color(hex: 0xB84E1D)         // oklch(.555 .15 42) persimmon: "again", "missed"
    static let warnSoft = Color(hex: 0xFEECE4)
    static let danger = Color(hex: 0xC13C3B)       // oklch(.55 .17 25) wrong, destructive
    static let dangerSoft = Color(hex: 0xFEEBE9)
    static let ice = Color(hex: 0x1F7FA2)          // oklch(.56 .10 228) streak freeze
    static let iceSoft = Color(hex: 0xDEF2FC)

    /// On the dark video cards: one pastel family (oklch L ≈ .83, C ≈ .09) for the tag capsules (black text),
    /// and brighter right/wrong marks that read on dark glass.
    enum OnDark {
        static let cyan = Color(hex: 0x81DAEF)
        static let warm = Color(hex: 0xFBBB87)
        static let mint = Color(hex: 0x8FE6C1)
        static let violet = Color(hex: 0xC2B1F8)
        static let pink = Color(hex: 0xF8A9C7)
        static let teal = Color(hex: 0x8BDCD6)
        static let gray = Color(hex: 0xC3C3CA)
        static let right = Color(hex: 0x62D286)
        static let wrong = Color(hex: 0xF66D67)
    }

    /// Japanese text: Hiragino Maru Gothic (rounded, ships with iOS), scaled with Dynamic Type.
    static func jp(_ size: CGFloat, bold: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(bold ? "HiraMaruProN-W4" : "HiraMaruProN-W4", size: size, relativeTo: style).weight(bold ? .bold : .regular)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

enum Skill: String, Codable, CaseIterable, Identifiable {
    case reading, listening, writing, speaking
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .reading: return "book.fill"
        case .listening: return "headphones"
        case .writing: return "pencil"
        case .speaking: return "mic.fill"
        }
    }
    var color: Color {
        switch self {
        // Equal OKLCH lightness (≈ .54) and similar chroma: four hues, one weight.
        case .reading: return Color(hex: 0x396CB7)     // oklch(.535 .13 258)
        case .listening: return Color(hex: 0x097F7C)   // oklch(.54 .095 192)
        case .writing: return Color(hex: 0x9D651C)     // oklch(.555 .11 68)
        case .speaking: return Color(hex: 0xB34460)    // oklch(.545 .145 8)
        }
    }
    var soft: Color {
        switch self {
        case .reading: return Color(hex: 0xE5EFFE)
        case .listening: return Color(hex: 0xDCF4F3)
        case .writing: return Color(hex: 0xFBEEDA)
        case .speaking: return Color(hex: 0xFFE8EB)
        }
    }
}

/// White rounded card with the soft violet lift shadow.
struct BrandCard: ViewModifier {
    var fill: Color = Brand.surface
    var padding: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The lift shadow belongs to the card shape only, never to the text on it.
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(fill)
                    .shadow(color: Color(hex: 0x29294D, opacity: 0.07), radius: 14, y: 6)
            )
    }
}

extension View {
    func brandCard(_ fill: Color = Brand.surface, padding: CGFloat = 18) -> some View { modifier(BrandCard(fill: fill, padding: padding)) }
}

/// Pill buttons: one violet primary per screen.
struct BrandButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    var kind: Kind = .primary
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(kind == .primary ? .white : kind == .secondary ? Brand.violetDeep : Brand.ink)
            // Flat: no drop shadow. Pressed = a slightly darker fill instead of a lift.
            .background(fill(pressed: configuration.isPressed), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }

    private func fill(pressed: Bool) -> Color {
        switch kind {
        case .primary: return pressed ? Brand.violetDeep : Brand.violet
        case .secondary: return pressed ? Brand.line : Brand.violetSoft
        case .quiet: return pressed ? Brand.line : Brand.mist
        }
    }
}

extension ButtonStyle where Self == BrandButtonStyle {
    static var brandPrimary: BrandButtonStyle { BrandButtonStyle(kind: .primary) }
    static var brandSecondary: BrandButtonStyle { BrandButtonStyle(kind: .secondary) }
    static var brandQuiet: BrandButtonStyle { BrandButtonStyle(kind: .quiet) }
}

struct SkillChip: View {
    let skill: Skill
    var body: some View {
        Label(skill.title, systemImage: skill.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(skill.color)
            .background(skill.soft, in: Capsule())
    }
}

/// Four dots: read · hear · write · say.
struct CoverageDots: View {
    let skills: Set<Skill>
    var size: CGFloat = 12
    var body: some View {
        HStack(spacing: size * 0.45) {
            ForEach(Skill.allCases) { s in
                Circle().fill(skills.contains(s) ? s.color : Brand.line).frame(width: size, height: size)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Skill.allCases.map { "\($0.title) \(skills.contains($0) ? "done" : "to do")" }.joined(separator: ", "))
    }
}

struct ProgressBar: View {
    let value: Double
    var color: Color = Brand.violet
    var height: CGFloat = 10
    var track: Color = Brand.line
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(color).frame(width: max(height, g.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: height)
    }
}

struct Ring: View {
    let value: Double
    var color: Color = Brand.violet
    var width: CGFloat = 12
    var body: some View {
        ZStack {
            Circle().stroke(Brand.line, lineWidth: width)
            Circle().trim(from: 0, to: min(1, value))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring, value: value)
        }
    }
}

/// Mascot pose.
enum MascotMood: String { case wave, map, sleepy, cheer, gift, freeze, idea }
struct MascotImage: View {
    let mood: MascotMood
    var size: CGFloat = 100
    /// A gentle idle bob (a living mascot, not a static sticker). Off with Reduce Motion.
    var animated = true
    @State private var up = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Image("mascot_\(mood.rawValue)").resizable().scaledToFit().frame(width: size, height: size)
            .offset(y: up ? -size * 0.03 : size * 0.01)
            .rotationEffect(.degrees(up ? -1.5 : 1.5), anchor: .bottom)
            .onAppear {
                guard animated, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { up = true }
            }
            .accessibilityHidden(true)
    }
}

/// Formats seconds as "1h 26m" / "9 min".
func durationText(_ s: Double) -> String {
    // Short sessions show seconds, so "58 s of Japanese" lines up with the percentage (no "0 min" next to 96%).
    let secs = Int(s.rounded())
    if secs < 60 { return "\(secs) s" }
    if secs < 600 { return secs % 60 == 0 ? "\(secs / 60) min" : "\(secs / 60) min \(secs % 60) s" }
    let m = Int((s / 60).rounded())
    if m >= 60 { return "\(m / 60)h \(m % 60)m" }
    return "\(m) min"
}
