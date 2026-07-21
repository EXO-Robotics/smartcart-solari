import SwiftUI

enum SmartCartAppearance: String, CaseIterable, Identifiable {
    case midnight
    case cleanLight

    static let storageKey = "smartcart.appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .midnight: "Midnight Market"
        case .cleanLight: "Clean Garden"
        }
    }

    var subtitle: String {
        switch self {
        case .midnight: "Dark charcoal surfaces with mint highlights"
        case .cleanLight: "Warm white surfaces with natural green accents"
        }
    }

    var symbol: String {
        switch self {
        case .midnight: "moon.stars.fill"
        case .cleanLight: "sun.max.fill"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .midnight: .dark
        case .cleanLight: .light
        }
    }
}

@MainActor
@Observable
final class SmartCartAppearanceController {
    private let defaults: UserDefaults

    var appearance: SmartCartAppearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: SmartCartAppearance.storageKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedValue = defaults.string(forKey: SmartCartAppearance.storageKey)
        appearance = SmartCartAppearance(rawValue: storedValue ?? "") ?? .midnight
    }

    var cleanLightModeEnabled: Bool {
        get { appearance == .cleanLight }
        set { appearance = newValue ? .cleanLight : .midnight }
    }
}

/// Adaptive SmartCart design system.
/// Midnight Market remains the default dark palette. Clean Garden is the
/// warm white, forest-green option inspired by the supplied product board.
enum SmartCartTheme {
    /// Apple platform controls must expose at least a 44-point effective hit
    /// region, even when their visible artwork is intentionally smaller.
    static let minimumHitTargetDimension: CGFloat = 44

    // Native semantic and named asset colors keep a stable ShapeStyle identity
    // while resolving correctly when the app-wide color scheme changes.
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let canvasRaise = Color(uiColor: .secondarySystemGroupedBackground)
    static let paper = Color(uiColor: .secondarySystemGroupedBackground)
    static let paperElevated = Color(uiColor: .tertiarySystemGroupedBackground)
    static let scannerSurface = Color("SmartCartScannerSurface")

    static let ink = Color(uiColor: .label)
    static let navy = ink
    static let secondaryInk = Color(uiColor: .secondaryLabel)
    static let mutedInk = Color(uiColor: .tertiaryLabel)

    // Calm leaf green in light mode; brighter in dark mode for legibility.
    static let green = Color("SmartCartLeafGreen")
    static let herb = green
    static let greenPressed = green.opacity(0.78)
    static let accentStrong = Color(uiColor: .systemMint)
    static let onAccent = Color(uiColor: .systemBackground)
    static let herbLight = green.opacity(0.12)

    static let walmartBlue = Color(uiColor: .systemBlue)
    static let onWalmartBlue = Color(uiColor: .systemBackground)
    static let walmartLight = Color(uiColor: .systemBlue).opacity(0.12)
    static let amber = Color(uiColor: .systemOrange)
    static let yellow = Color(uiColor: .systemYellow)
    static let coral = Color(uiColor: .systemRed)
    static let purple = Color(uiColor: .systemPurple)

    static let border = Color(uiColor: .separator)
    static let borderBright = Color(uiColor: .opaqueSeparator)
    static let borderStrong = green.opacity(0.42)
    static let softShadow = Color.black.opacity(0.22)
    static let mintGlow = green.opacity(0.18)

    // Compatibility aliases for the original prototype components.
    static let tomato = coral
    static let peach = amber.opacity(0.16)
    static let butter = yellow

    static let cardRadius: CGFloat = 22

}

/// One restrained motion language for the app: tactile controls, workspace
/// changes, and the small number of signature transformations.
enum SmartCartMotion {
    static let quick = Animation.easeOut(duration: 0.12)
    static let standard = Animation.spring(response: 0.30, dampingFraction: 0.88)
    static let signature = Animation.spring(response: 0.52, dampingFraction: 0.86)
}

enum SmartCartTransitionID: Hashable {
    case recipeWorkspace
    case shoppingWorkspace
}

/// Viewport-fixed wood texture. Scroll views move over this image instead of
/// stretching or repeating it, which keeps the grain stable during scrolling.
struct WoodGrainBackground: View {
    var body: some View {
        GeometryReader { geometry in
            SmartCartTheme.canvas

            Image("SmartCartWoodBackground")
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Concave top edge for an expanded wood-backed drawer. The outer edges rise
/// behind the pull tab while the center begins below it, creating a U-shaped
/// wrap without exposing wood when `depth` is zero in the collapsed state.
struct SmartCartDrawerWoodWrapShape: Shape {
    var depth: CGFloat

    var animatableData: CGFloat {
        get { depth }
        set { depth = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clampedDepth = min(max(depth, 0), min(rect.width / 2, rect.height))

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.minX + clampedDepth, y: rect.minY + clampedDepth),
            control1: CGPoint(x: rect.minX + clampedDepth * 0.55, y: rect.minY),
            control2: CGPoint(
                x: rect.minX + clampedDepth,
                y: rect.minY + clampedDepth * 0.45
            )
        )
        path.addLine(
            to: CGPoint(x: rect.maxX - clampedDepth, y: rect.minY + clampedDepth)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(
                x: rect.maxX - clampedDepth,
                y: rect.minY + clampedDepth * 0.45
            ),
            control2: CGPoint(x: rect.maxX - clampedDepth * 0.55, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Shared smoked-glass surface used by the Home action card and the exposed
/// tips of wood-backed pull-up drawers.
struct SmartCartSmokedGlassSurface: View {
    @Environment(\.colorScheme) private var colorScheme

    let radius: CGFloat
    let darkness: Double
    let showsBorder: Bool

    init(radius: CGFloat, darkness: Double, showsBorder: Bool = true) {
        self.radius = radius
        self.darkness = darkness
        self.showsBorder = showsBorder
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        shape
            .fill(.ultraThinMaterial)
            .overlay {
                shape.fill(
                    colorScheme == .light
                        ? Color.white.opacity(min(0.82, 0.62 + darkness * 0.25))
                        : Color.black.opacity(darkness)
                )
            }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: colorScheme == .light
                            ? [Color.white.opacity(0.44), Color.clear, Color.black.opacity(0.04)]
                            : [Color.white.opacity(0.10), Color.clear, Color.black.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay {
                if showsBorder {
                    shape.stroke(
                        colorScheme == .light ? Color.black.opacity(0.12) : Color.white.opacity(0.22),
                        lineWidth: 1
                    )
                }
            }
            .shadow(
                color: .black.opacity(colorScheme == .light ? 0.14 : 0.28),
                radius: 20,
                y: 10
            )
    }
}

/// Draws the drawer material directly into its pull-tab shape. Keeping the
/// material's render bounds identical to the visible shape avoids the faint
/// rectangular backdrop band that post-clipping can expose in either appearance.
struct SmartCartDrawerGlassSurface<SurfaceShape: Shape>: View {
    @Environment(\.colorScheme) private var colorScheme

    let shape: SurfaceShape
    let darkness: Double

    var body: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay {
                shape.fill(
                    colorScheme == .light
                        ? Color.white.opacity(min(0.82, 0.62 + darkness * 0.25))
                        : Color.black.opacity(darkness)
                )
            }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: colorScheme == .light
                            ? [Color.white.opacity(0.44), Color.clear, Color.black.opacity(0.04)]
                            : [Color.white.opacity(0.10), Color.clear, Color.black.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
    }
}

/// Shared full-screen food photography for primary app surfaces. The adaptive
/// veil preserves semantic label contrast in both supported appearance modes.
struct SmartCartFoodBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                colorScheme == .light ? Color.white : Color.black

                Image("SmartCartHomeBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                if colorScheme == .light {
                    Color.white.opacity(0.62)

                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.34),
                            Color.clear,
                            Color.white.opacity(0.24)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                } else {
                    Color.black.opacity(0.46)

                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.34),
                            Color.clear,
                            Color.black.opacity(0.24)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A restrained physical edge for cards on both wood backgrounds. The darker
/// lower rim, fine top highlight, and compact shadow create depth
/// without turning the interface into a skeuomorphic stack of panels.
private struct SmartCartCardEdgeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let radius: CGFloat
    let elevated: Bool

    func body(content: Content) -> some View {
        let isLight = colorScheme == .light
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        content
            .clipShape(shape)
            .overlay {
                if isLight {
                    shape
                        .strokeBorder(
                            Color.black.opacity(elevated ? 0.22 : 0.17),
                            lineWidth: elevated ? 1.15 : 1
                        )

                    shape
                        .inset(by: 1)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.92),
                                    Color.white.opacity(0.16),
                                    Color.black.opacity(elevated ? 0.12 : 0.08)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.35
                        )
                } else {
                    shape
                        .strokeBorder(
                            Color.black.opacity(elevated ? 0.82 : 0.70),
                            lineWidth: elevated ? 1.15 : 1
                        )

                    shape
                        .inset(by: 1)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    Color.white.opacity(0.025),
                                    Color.black.opacity(elevated ? 0.50 : 0.38)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.35
                        )
                }
            }
            .shadow(
                color: isLight
                    ? Color.black.opacity(elevated ? 0.15 : 0.10)
                    : Color.black.opacity(elevated ? 0.48 : 0.32),
                radius: elevated ? (isLight ? 8 : 9) : (isLight ? 5 : 6),
                x: 0,
                y: elevated ? 5 : 3
            )
    }
}

extension View {
    /// Screen-level background using SmartCart's shared food photography.
    func smartCartBackground() -> some View {
        background {
            SmartCartFoodBackground()
                .ignoresSafeArea()
        }
    }

    func smartCartCard(padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .background(SmartCartTheme.paper)
            .smartCartCardEdge()
    }

    /// Adds the shared rounded rim and compact light-mode depth to any
    /// existing card surface without changing its fill color or padding.
    func smartCartCardEdge(
        radius: CGFloat = SmartCartTheme.cardRadius,
        elevated: Bool = true
    ) -> some View {
        modifier(SmartCartCardEdgeModifier(radius: radius, elevated: elevated))
    }

    func smartCartShadow() -> some View {
        shadow(color: SmartCartTheme.softShadow, radius: 22, x: 0, y: 12)
    }

    /// Faint mint halo for the most important surface on a screen.
    func smartCartGlow(_ color: Color = SmartCartTheme.mintGlow) -> some View {
        shadow(color: color, radius: 26, x: 0, y: 0)
    }

    func smartField() -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(SmartCartTheme.canvasRaise)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(SmartCartTheme.border, lineWidth: 1)
            }
    }

    /// Expands the effective interaction geometry without forcing the visible
    /// control artwork to grow. Apply this to the control itself, after styling
    /// its label, so each control remains independently focusable.
    func smartCartMinimumHitTarget() -> some View {
        frame(
            minWidth: SmartCartTheme.minimumHitTargetDimension,
            minHeight: SmartCartTheme.minimumHitTargetDimension
        )
        .contentShape(Rectangle())
    }

    /// Uppercase mono micro-label, the design system's "eyebrow" voice.
    func smartEyebrow(_ color: Color = SmartCartTheme.green) -> some View {
        self
            .font(.system(.caption2, design: .monospaced, weight: .bold))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    /// Uses the platform's spatial navigation transition on iOS 18 and newer.
    /// Earlier systems retain the native NavigationStack push animation.
    func smartCartTransitionSource<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID
    ) -> some View {
        modifier(SmartCartTransitionSourceModifier(id: id, namespace: namespace))
    }

    func smartCartNavigationZoom<ID: Hashable>(
        sourceID: ID,
        in namespace: Namespace.ID
    ) -> some View {
        modifier(SmartCartNavigationZoomModifier(sourceID: sourceID, namespace: namespace))
    }
}

private struct SmartCartTransitionSourceModifier<ID: Hashable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let id: ID
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), !reduceMotion {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

private struct SmartCartNavigationZoomModifier<ID: Hashable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let sourceID: ID
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), !reduceMotion {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
    }
}

struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : SmartCartMotion.quick, value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(isEnabled ? SmartCartTheme.onAccent : SmartCartTheme.mutedInk)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                isEnabled
                    ? (configuration.isPressed ? SmartCartTheme.greenPressed : SmartCartTheme.green)
                    : SmartCartTheme.paperElevated
            )
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                if !isEnabled {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(SmartCartTheme.border, lineWidth: 1)
                }
            }
            .shadow(
                color: isEnabled ? SmartCartTheme.mintGlow : .clear,
                radius: configuration.isPressed ? 8 : 16,
                y: 4
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(SmartCartTheme.ink)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(configuration.isPressed ? SmartCartTheme.paperElevated : SmartCartTheme.paper.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(
                        configuration.isPressed ? SmartCartTheme.borderStrong : SmartCartTheme.borderBright,
                        lineWidth: 1
                    )
            }
    }
}

struct BlueButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(SmartCartTheme.onWalmartBlue)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(configuration.isPressed ? SmartCartTheme.walmartBlue.opacity(0.82) : SmartCartTheme.walmartBlue)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .shadow(color: SmartCartTheme.walmartBlue.opacity(0.22), radius: configuration.isPressed ? 8 : 16, y: 4)
    }
}
