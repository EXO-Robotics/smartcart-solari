import SwiftUI

struct WeeklyMealCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let model: WeeklyMealDisplayModel
    let isFocused: Bool
    let fixedHeight: CGFloat?
    let onOpen: () -> Void
    let onShop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                artwork
                content
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(model.accessibilitySummary)
            .accessibilityHint("Double tap to view recipe")
            .accessibilityIdentifier("weekly-meal-card-\(model.id.rawValue)")
            .accessibilityAction(.default, onOpen)
            .accessibilityAction(named: "Shop This Meal", onShop)

            focusedActions
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
                .opacity(isFocused ? 1 : 0)
                .offset(y: isFocused && !reduceMotion ? 0 : 4)
                .allowsHitTesting(isFocused)
                .accessibilityHidden(!isFocused)
        }
        .frame(maxWidth: .infinity, minHeight: fixedHeight, maxHeight: fixedHeight, alignment: .top)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(SmartCartTheme.paper)
                SmartCartSmokedGlassSurface(
                    radius: 26,
                    darkness: colorScheme == .dark ? 0.34 : 0.12
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(
                    isFocused ? SmartCartTheme.green.opacity(0.72) : Color.white.opacity(colorScheme == .dark ? 0.16 : 0.04),
                    lineWidth: isFocused ? 1.5 : 1
                )
        }
    }

    private var artwork: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: artworkColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: model.slot.symbolName)
                .font(.system(size: 62, weight: .light))
                .foregroundStyle(.white.opacity(0.88))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)

            HStack(spacing: 7) {
                Text(model.slot.displayName)
                if model.isFeatured {
                    Text("Featured")
                }
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.black.opacity(0.34), in: Capsule())
            .padding(14)
        }
        .frame(height: 142)
        .clipped()
        .accessibilityHidden(true)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.title)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(SmartCartTheme.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let tag = model.primaryTag {
                tagBadge(tag)
            }

            Text(model.shortDescription)
                .font(.subheadline)
                .foregroundStyle(SmartCartTheme.secondaryInk)
                .lineLimit(isFocused ? 3 : 1)
                .frame(maxHeight: isFocused ? 60 : 20, alignment: .top)
                .opacity(isFocused ? 1 : 0.78)

            focusedDetails
                .opacity(isFocused ? 1 : 0)
                .offset(y: isFocused && !reduceMotion ? 0 : 4)
                .accessibilityHidden(!isFocused)
        }
        .padding(.horizontal, 18)
        .padding(.top, 15)
        .padding(.bottom, 13)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : SmartCartMotion.standard, value: isFocused)
    }

    private var focusedDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let calories = model.caloriesPerServing,
               let protein = model.proteinGramsPerServing {
                Text("Est. \(calories) cal · Est. \(protein.formatted()) g protein")
            }
            Text("\(model.totalMinutes) min · Serves \(model.defaultServings)")
            if let cost = model.costPerServingText {
                Text(cost)
            }
#if DEBUG
            if model.costPerServingText == nil,
               model.costStatus == .requiresVerification {
                Text("Cost estimate pending")
                    .foregroundStyle(SmartCartTheme.mutedInk)
            }
#endif

            if let secondTag = model.secondaryTag {
                tagBadge(secondTag)
                    .padding(.top, 2)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(SmartCartTheme.secondaryInk)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
    }

    private var focusedActions: some View {
        HStack(spacing: 10) {
            Button("Shop This Meal", action: onShop)
                .buttonStyle(WeeklyMealPrimaryButtonStyle())
                .accessibilityIdentifier("weekly-meal-shop-\(model.id.rawValue)")

            Button("View Recipe", action: onOpen)
                .buttonStyle(WeeklyMealSecondaryButtonStyle())
                .accessibilityIdentifier("weekly-meal-view-\(model.id.rawValue)")
        }
        .frame(minHeight: 48)
    }

    private func tagBadge(_ tag: MerchandisingTag) -> some View {
        Label(tag.displayName, systemImage: tag.symbolName)
            .font(.caption2.weight(.bold))
            .foregroundStyle(SmartCartTheme.green)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(SmartCartTheme.herbLight, in: Capsule())
    }

    private var artworkColors: [Color] {
        switch model.slot {
        case .breakfast: [Color.orange.opacity(0.92), Color.yellow.opacity(0.50)]
        case .lunch: [SmartCartTheme.green.opacity(0.92), Color.teal.opacity(0.62)]
        case .dinner: [Color.indigo.opacity(0.88), Color.purple.opacity(0.62)]
        case .snack: [Color.pink.opacity(0.80), Color.orange.opacity(0.58)]
        }
    }
}

private struct WeeklyMealPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.bold))
            .foregroundStyle(.black.opacity(0.84))
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(configuration.isPressed ? SmartCartTheme.greenPressed : SmartCartTheme.green)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct WeeklyMealSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.bold))
            .foregroundStyle(SmartCartTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Color.white.opacity(configuration.isPressed ? 0.06 : 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(SmartCartTheme.border, lineWidth: 1)
            }
    }
}
