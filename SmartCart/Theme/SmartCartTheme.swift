import SwiftUI

enum SmartCartTheme {
    static let canvas = Color(red: 0.968, green: 0.976, blue: 0.982)
    static let paper = Color.white
    static let navy = Color(red: 0.035, green: 0.105, blue: 0.225)
    static let ink = navy
    static let secondaryInk = Color(red: 0.31, green: 0.36, blue: 0.43)
    static let green = Color(red: 0.0, green: 0.57, blue: 0.27)
    static let herb = green
    static let greenPressed = Color(red: 0.0, green: 0.46, blue: 0.22)
    static let herbLight = Color(red: 0.89, green: 0.97, blue: 0.92)
    static let walmartBlue = Color(red: 0.0, green: 0.44, blue: 0.80)
    static let walmartLight = Color(red: 0.89, green: 0.95, blue: 1.0)
    static let amber = Color(red: 0.95, green: 0.62, blue: 0.04)
    static let yellow = Color(red: 1.0, green: 0.75, blue: 0.05)
    static let coral = Color(red: 0.88, green: 0.25, blue: 0.25)
    static let purple = Color(red: 0.43, green: 0.34, blue: 0.80)
    static let border = Color(red: 0.86, green: 0.89, blue: 0.92)
    static let softShadow = Color(red: 0.03, green: 0.10, blue: 0.22).opacity(0.08)

    // Compatibility aliases for the original prototype components.
    static let tomato = coral
    static let peach = Color(red: 1.0, green: 0.91, blue: 0.83)
    static let butter = Color(red: 1.0, green: 0.88, blue: 0.42)

    static let cardRadius: CGFloat = 20
}

extension View {
    func smartCartCard(padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .background(SmartCartTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: SmartCartTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SmartCartTheme.cardRadius, style: .continuous)
                    .stroke(SmartCartTheme.border, lineWidth: 1)
            }
    }

    func smartCartShadow() -> some View {
        shadow(color: SmartCartTheme.softShadow, radius: 18, x: 0, y: 8)
    }

    func smartField() -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(SmartCartTheme.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(SmartCartTheme.border, lineWidth: 1)
            }
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                isEnabled
                    ? (configuration.isPressed ? SmartCartTheme.greenPressed : SmartCartTheme.green)
                    : SmartCartTheme.secondaryInk.opacity(0.35)
            )
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(SmartCartTheme.navy)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(configuration.isPressed ? SmartCartTheme.canvas : SmartCartTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(SmartCartTheme.border, lineWidth: 1)
            }
    }
}

struct BlueButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(configuration.isPressed ? SmartCartTheme.walmartBlue.opacity(0.82) : SmartCartTheme.walmartBlue)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}
