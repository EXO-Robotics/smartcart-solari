import SwiftUI

struct SmartCartLogo: View {
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 7 : 10) {
            ZStack {
                Image(systemName: "cart.fill.badge.plus")
                    .font(.system(size: compact ? 22 : 29, weight: .bold))
                    .foregroundStyle(GatherTheme.green)
            }
            .frame(width: compact ? 29 : 38, height: compact ? 29 : 38)

            Text("Smart")
                .foregroundStyle(GatherTheme.navy)
            + Text("Cart")
                .foregroundStyle(GatherTheme.green)
        }
        .font(.system(size: compact ? 22 : 31, weight: .heavy, design: .rounded))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SmartCart")
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(GatherTheme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(GatherTheme.secondaryInk)
                }
            }

            Spacer(minLength: 10)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GatherTheme.green)
            }
        }
    }
}

struct ImportActionTile: View {
    let method: ImportMethod
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: method.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(method.tint)
                    .frame(width: 39, height: 39)
                    .background(method.tint.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(homeTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(GatherTheme.navy)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .allowsTightening(true)
                    Text(method.subtitle)
                        .font(.caption2)
                        .foregroundStyle(GatherTheme.secondaryInk)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(GatherTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(GatherTheme.border, lineWidth: 1)
            }
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var homeTitle: String {
        switch method {
        case .camera: "Take photo"
        case .photoLibrary: "Upload photo"
        case .recipeLink: "Paste link"
        case .pinterest: "Pinterest"
        case .recipeText: "Paste recipe"
        case .sample: "Try sample"
        }
    }
}

struct RecipeHeroCard: View {
    let recipe: Recipe
    var actionTitle = "Start shopping"
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.96, green: 0.78, blue: 0.30),
                        Color(red: 0.94, green: 0.45, blue: 0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 180, height: 180)
                    .offset(x: 92, y: -48)

                Image(systemName: recipe.heroSymbol)
                    .font(.system(size: 60, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: Color.black.opacity(0.18), radius: 18, y: 9)
            }
            .frame(height: 150)

            VStack(alignment: .leading, spacing: 13) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(recipe.title)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(GatherTheme.navy)
                        .lineLimit(2)
                    HStack(spacing: 14) {
                        Label("\(recipe.servings) servings", systemImage: "person.2.fill")
                        Label("\(recipe.totalMinutes)m", systemImage: "clock.fill")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GatherTheme.secondaryInk)
                }

                if let action {
                    Button(action: action) {
                        HStack {
                            Text(actionTitle)
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(16)
            .background(GatherTheme.paper)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(GatherTheme.border, lineWidth: 1)
        }
        .gatherShadow()
    }
}

struct WorkflowHeader: View {
    let step: Int
    let total: Int
    let eyebrow: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.heavy))
                    .tracking(0.9)
                    .foregroundStyle(GatherTheme.green)
                Spacer()
                Text("Step \(step) of \(total)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GatherTheme.secondaryInk)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(GatherTheme.border)
                    Capsule()
                        .fill(GatherTheme.green)
                        .frame(width: proxy.size.width * CGFloat(step) / CGFloat(total))
                }
            }
            .frame(height: 5)

            Text(title)
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(GatherTheme.navy)
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(GatherTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct JourneyStepCard: View {
    let number: Int
    let symbol: String
    let title: String
    let subtitle: String
    var isActive = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(isActive ? .white : GatherTheme.green)
                .frame(width: 40, height: 40)
                .background(isActive ? GatherTheme.green : GatherTheme.herbLight)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(GatherTheme.navy)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(GatherTheme.secondaryInk)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: 88)
        .padding(.vertical, 12)
        .background(GatherTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isActive ? GatherTheme.green.opacity(0.55) : GatherTheme.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number), \(title), \(subtitle)")
    }
}

struct IngredientConfidenceBadge: View {
    let confidence: IngredientConfidence

    var body: some View {
        Label(confidence.label, systemImage: confidence.symbol)
            .font(.caption2.weight(.bold))
            .foregroundStyle(confidence.color)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(confidence.color.opacity(0.10))
            .clipShape(Capsule())
    }
}

struct StatusPill: View {
    let title: String
    let symbol: String
    var color: Color = GatherTheme.green

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
    }
}

struct StoreMark: View {
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(GatherTheme.walmartBlue)
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(GatherTheme.yellow)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct ProductIcon: View {
    let product: ProductCandidate
    var size: CGFloat = 64

    var body: some View {
        Image(systemName: product.symbol)
            .font(.system(size: size * 0.37, weight: .semibold))
            .foregroundStyle(GatherTheme.walmartBlue)
            .frame(width: size, height: size)
            .background(GatherTheme.walmartLight)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .stroke(GatherTheme.walmartBlue.opacity(0.12), lineWidth: 1)
            }
    }
}

struct InfoBanner: View {
    let symbol: String
    let title: String
    let message: String
    var color: Color = GatherTheme.walmartBlue

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.10))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GatherTheme.navy)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(GatherTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(color.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(color.opacity(0.14), lineWidth: 1)
        }
    }
}

struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(GatherTheme.yellow)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(GatherTheme.navy.opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 29, weight: .semibold))
                .foregroundStyle(GatherTheme.green)
                .frame(width: 66, height: 66)
                .background(GatherTheme.herbLight)
                .clipShape(Circle())
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(GatherTheme.navy)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(GatherTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        .background(GatherTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: GatherTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GatherTheme.cardRadius, style: .continuous)
                .stroke(GatherTheme.border, lineWidth: 1)
        }
    }
}

struct BottomActionBar<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            content
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }
}
