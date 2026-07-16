import SwiftUI

struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(GatherTheme.ink)

            Spacer()

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GatherTheme.herb)
            }
        }
    }
}

struct StoreMark: View {
    let store: GroceryStore
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: store.symbol)
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(store.color)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct StorePill: View {
    let store: GroceryStore
    var isSelected = true

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(store.color)
                .frame(width: 8, height: 8)
            Text(store.shortName)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(isSelected ? GatherTheme.ink : GatherTheme.secondaryInk)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? GatherTheme.paper : Color.white.opacity(0.45))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(isSelected ? GatherTheme.border : Color.clear, lineWidth: 1)
        }
    }
}

struct RecipeCard: View {
    let recipe: Recipe
    var compact = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: recipe.gradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 150, height: 150)
                .offset(x: 110, y: -75)

            VStack(alignment: .leading, spacing: 8) {
                Text(recipe.emoji)
                    .font(.system(size: compact ? 40 : 52))
                    .shadow(color: Color.black.opacity(0.08), radius: 10, y: 6)

                Spacer(minLength: 8)

                Text(recipe.title)
                    .font(.system(size: compact ? 18 : 21, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    Label("\(recipe.timeMinutes)m", systemImage: "clock")
                    Label("\(recipe.servings)", systemImage: "person.2.fill")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
            }
            .padding(18)
        }
        .frame(width: compact ? 186 : 218, height: compact ? 214 : 250)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        }
    }
}

struct StatChip: View {
    let symbol: String
    let text: String
    var color: Color = GatherTheme.herb

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
    }
}

struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(GatherTheme.butter)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(GatherTheme.ink.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(GatherTheme.herb)
                .frame(width: 70, height: 70)
                .background(GatherTheme.herbLight)
                .clipShape(Circle())
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(GatherTheme.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(GatherTheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .gatherCard()
    }
}
