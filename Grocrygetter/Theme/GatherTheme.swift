import SwiftUI

enum GatherTheme {
    static let canvas = Color(red: 0.969, green: 0.957, blue: 0.925)
    static let paper = Color(red: 1.0, green: 0.995, blue: 0.976)
    static let ink = Color(red: 0.105, green: 0.125, blue: 0.105)
    static let secondaryInk = Color(red: 0.36, green: 0.38, blue: 0.33)
    static let herb = Color(red: 0.18, green: 0.38, blue: 0.25)
    static let herbLight = Color(red: 0.84, green: 0.90, blue: 0.81)
    static let tomato = Color(red: 0.89, green: 0.30, blue: 0.18)
    static let peach = Color(red: 0.98, green: 0.76, blue: 0.57)
    static let butter = Color(red: 0.97, green: 0.89, blue: 0.59)
    static let border = Color.black.opacity(0.07)

    static let cardRadius: CGFloat = 24
}

extension View {
    func gatherCard(padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .background(GatherTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: GatherTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: GatherTheme.cardRadius, style: .continuous)
                    .stroke(GatherTheme.border, lineWidth: 1)
            }
    }

    func gatherShadow() -> some View {
        shadow(color: Color.black.opacity(0.07), radius: 18, x: 0, y: 8)
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(configuration.isPressed ? GatherTheme.herb.opacity(0.8) : GatherTheme.herb)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
