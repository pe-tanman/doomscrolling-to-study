import SwiftUI

// MARK: - Palette (reference colours)
//
// Upscroll palette v4. Generated and verified by tools/palette/palette.py: change a ramp there, re-run it
// (it checks 81 text/background pairs for WCAG AA and APCA, plus colour-blind separation), then paste its
// `--swift` output here. Views never use these ramps directly; they use the semantic `Brand` roles below.
//
// The ramps are OKLCH with fixed lightness per step, so every hue's 100 (or 700) carries the same weight.
// One rule holds for every hue:
//     600 is text-safe on white, on 50 and on 100 (≥ 4.6:1), and white text on 600 passes AA (≥ 5.3:1).
// 50/100 = tints (chips, tiles, wells) · 300 = bright fills · 600 = the colour itself · 700+ = deep accents.

/// One hue from 50 (palest) to 900 (deepest).
struct Ramp {
    let s50, s100, s200, s300, s400, s500, s600, s700, s800, s900: Color
    init(_ h: UInt32...) {
        precondition(h.count == 10)
        (s50, s100, s200, s300, s400) = (Color(hex: h[0]), Color(hex: h[1]), Color(hex: h[2]), Color(hex: h[3]), Color(hex: h[4]))
        (s500, s600, s700, s800, s900) = (Color(hex: h[5]), Color(hex: h[6]), Color(hex: h[7]), Color(hex: h[8]), Color(hex: h[9]))
    }
}

enum Palette {
    /// 藍 ai — primary; the lavender→periwinkle sky of the art
    static let indigo = Ramp(0xF6F6FF, 0xEBEBFF, 0xD8D8FF, 0xC2C2FF, 0xA5A4FF, 0x8782F6, 0x615ACF, 0x4D46B1, 0x39338D, 0x252165)
    /// indigo-tinted greys; ink is a deep indigo, never flat black
    static let neutral = Ramp(0xF7F6FC, 0xF0EFF8, 0xE3E1ED, 0xC6C6D4, 0xA6A6B8, 0x848499, 0x6D6D87, 0x555674, 0x3F4063, 0x292850)
    /// 桜 sakura — the blossoms; skill: speaking
    static let sakura = Ramp(0xFFF3F7, 0xFDE6ED, 0xFBCEDD, 0xFAB1C9, 0xEF8CAF, 0xD86A92, 0xB0416C, 0x942E55, 0x741E3F, 0x53102A)
    /// 山吹 yamabuki — rewards, the next unlock; skill: writing
    static let gold = Ramp(0xFBF7EB, 0xF5ECD7, 0xEEDBB0, 0xF6BF51, 0xDCA534, 0xC18700, 0x8F6100, 0x7A4F00, 0x5F3B00, 0x432600)
    /// 空 sora — skill: reading
    static let sky = Ramp(0xEFF8FF, 0xDFEFFD, 0xC0E1FC, 0x9AD0FC, 0x6CB7F5, 0x449AE1, 0x016DB5, 0x005C9E, 0x00457C, 0x002E59)
    /// 浅葱 asagi teal — skill: listening
    static let asagi = Ramp(0xEFF9F9, 0xDFF1F1, 0xBFE5E4, 0x96D7D5, 0x60C2C0, 0x27A8A5, 0x007774, 0x006764, 0x004F4C, 0x003634)
    /// 抹茶 matcha — right, learned, success
    static let matcha = Ramp(0xF0FAF1, 0xE1F2E3, 0xC4E7CA, 0x9EDAAA, 0x6EC686, 0x3FAC66, 0x007B3F, 0x006C38, 0x00522B, 0x00381C)
    /// 柿 kaki persimmon — "again", gentle warning
    static let kaki = Ramp(0xFFF5ED, 0xFDE8DB, 0xFBD3B9, 0xFBB88D, 0xF29659, 0xDB742A, 0xAB4E00, 0x8F3E00, 0x6F2D00, 0x4E1C00)
    /// 紅 beni crimson — wrong, destructive
    static let beni = Ramp(0xFFF4F3, 0xFFE6E4, 0xFFCFCB, 0xFFB2AD, 0xFF8783, 0xEF5B5D, 0xC72C38, 0xA61126, 0x830019, 0x5C000F)
    /// 氷 kōri — streak freeze
    static let ice = Ramp(0xEFF9FC, 0xE0F0F7, 0xC2E2F1, 0x9BD2EB, 0x6CBBDE, 0x40A0C7, 0x007398, 0x006283, 0x004A65, 0x003347)
}

// MARK: - Brand (semantic roles)

/// What views use. Each role names a job, not a hue, and points at one palette step.
enum Brand {
    // Text and surfaces (light dashboard)
    static let ink = Palette.neutral.s900          // primary text (12.9:1 on the page)
    static let ink2 = Palette.neutral.s700         // secondary text, icons (6.6:1)
    static let ink3 = Palette.neutral.s500         // chevrons, close buttons, inactive (≥ 3:1, icons only — not for text)
    static let sky = Palette.neutral.s50           // page background
    static let surface = Color.white               // cards
    static let mist = Palette.neutral.s100         // wells, quiet chips, quiet buttons
    static let line = Palette.neutral.s200         // hairlines, empty progress tracks
    /// Dark scrim at the bottom of full-bleed pictures, so white text on them stays readable.
    static let scrim = Palette.indigo.s900

    // Primary: indigo
    static let violet = Palette.indigo.s600        // buttons, tint, progress, selected
    static let violetSoft = Palette.indigo.s100    // secondary buttons, selected chips
    static let violetDeep = Palette.indigo.s700    // accent text, pressed primary
    /// The hero cards (next unlock): deeper than the buttons so gold and white text both read on them.
    static let heroGradient = LinearGradient(colors: [Palette.indigo.s700, Palette.indigo.s800],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)

    // Accents
    static let sakura = Palette.sakura.s300        // blossom fills, confetti
    static let sakuraSoft = Palette.sakura.s100
    static let cream = Palette.gold.s50            // warm wells
    static let sun = Palette.gold.s300             // yamabuki: bars, rings, coins — fills only, never text on white
    static let sunSoft = Palette.gold.s100
    static let sunDeep = Palette.gold.s600         // gold as text or icon (rewards, "today", "new")

    // Status: each colour is text-safe on white and on its own Soft tint
    static let success = Palette.matcha.s600       // right, learned, done
    static let successSoft = Palette.matcha.s100
    static let warn = Palette.kaki.s600            // "again", missed — always with an icon or word
    static let warnSoft = Palette.kaki.s100
    static let danger = Palette.beni.s600          // wrong, destructive — always with an icon or word
    static let dangerSoft = Palette.beni.s100
    static let ice = Palette.ice.s600              // streak freeze
    static let iceSoft = Palette.ice.s100

    /// On the indigo hero cards.
    enum OnIndigo {
        static let gold = Color(hex: 0xFCDA86)     // oklch(.90 .11 88): labels and fills (≥ 5.5:1 on the card)
        static let muted = Palette.indigo.s50      // secondary text (not white at reduced opacity)
    }

    /// On the dark glass cards over video. One bright pastel family (oklch L ≈ .80–.88) that always takes
    /// black text when used as a capsule fill (≥ 10:1), plus the highlight gold and the right/wrong marks.
    enum OnDark {
        static let gold = Color(hex: 0xFFD15A)     // the highlight: the Japanese word, the answer, the main button
        static let cyan = Color(hex: 0x7FDEF5)
        static let peach = Color(hex: 0xFBBA8F)
        static let mint = Color(hex: 0x93E6BD)
        static let violet = Color(hex: 0xBFB2F9)
        static let pink = Color(hex: 0xF8A9C7)
        static let lime = Color(hex: 0xC5E68C)
        static let gray = Color(hex: 0xC6C6CF)
        static let right = Color(hex: 0x86F09F)
        static let wrong = Color(hex: 0xFFB7C7)    // rose, not red: stays apart from `right` for red-green colour blindness
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
    /// Four brand hues: sky, asagi teal, yamabuki gold, sakura. Each is the ramp's 600, so it's text-safe on
    /// white and on `soft`. Skills always show with their icon or in a fixed order, so colour is never the only cue.
    private var ramp: Ramp {
        switch self {
        case .reading: return Palette.sky
        case .listening: return Palette.asagi
        case .writing: return Palette.gold
        case .speaking: return Palette.sakura
        }
    }
    var color: Color { ramp.s600 }
    var soft: Color { ramp.s100 }
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
                    .shadow(color: Brand.ink.opacity(0.07), radius: 14, y: 6)
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
