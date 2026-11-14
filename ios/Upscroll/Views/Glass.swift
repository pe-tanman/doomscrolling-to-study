import SwiftUI

/// Liquid Glass on iOS 26+, the closest material on older iOS.
/// Glass is for the floating layer (cards, controls) over the video, never for the video itself.
extension View {
    @ViewBuilder
    func glass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            let base: Glass = tint.map { Glass.regular.tint($0) } ?? .regular
            self.glassEffect(interactive ? base.interactive() : base, in: shape)
        } else {
            self.background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    if let tint { shape.fill(tint) }
                }
            }
        }
    }

    func glass(cornerRadius: CGFloat, tint: Color? = nil, interactive: Bool = false) -> some View {
        glass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), tint: tint, interactive: interactive)
    }

    /// Primary action (Continue): prominent glass tinted with the accent; solid fill before iOS 26.
    @ViewBuilder
    func prominentGlassButton(_ color: Color) -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent).tint(color)
        } else {
            self.buttonStyle(.borderedProminent).tint(color)
        }
    }

    @ViewBuilder
    func glassButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
