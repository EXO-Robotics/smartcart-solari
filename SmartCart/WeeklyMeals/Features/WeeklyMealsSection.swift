import SwiftUI

struct WeeklyMealsSection: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let collection: ResolvedWeeklyMealCollection?
    private let models: [WeeklyMealDisplayModel]
    let onOpen: (CuratedRecipeID) -> Void
    let onShop: (CuratedRecipeID) -> Void
    let onSeeAll: () -> Void

    init(
        onOpen: @escaping (CuratedRecipeID) -> Void,
        onShop: @escaping (CuratedRecipeID) -> Void,
        onSeeAll: @escaping () -> Void
    ) {
        let resolved = try? BundledWeeklyMealRepository().activeCollection(
            on: Date(),
            calendar: Calendar.autoupdatingCurrent
        )
        collection = resolved
        models = resolved.map { WeeklyMealDisplayModelFactory.makeModels(from: $0) } ?? []
        self.onOpen = onOpen
        self.onShop = onShop
        self.onSeeAll = onSeeAll
    }

    var body: some View {
        if let collection, !models.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                heading

                if dynamicTypeSize.isAccessibilitySize {
                    accessibilityList
                } else {
                    WeeklyMealMagnifyingCarousel(
                        models: models,
                        onOpen: onOpen,
                        onShop: onShop
                    )
                }
            }
            .onAppear {
                _ = collection.id
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("This Week’s Meals")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(SmartCartTheme.ink)
                Spacer(minLength: 10)
                Button("See All", action: onSeeAll)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(SmartCartTheme.green)
                    .accessibilityIdentifier("weekly-meals-see-all")
            }

            Text("Two breakfasts, two lunches, two dinners, and two snacks—ready to add to your shopping trip.")
                .font(.subheadline)
                .foregroundStyle(SmartCartTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accessibilityList: some View {
        LazyVStack(spacing: 14) {
            ForEach(models) { model in
                WeeklyMealCard(
                    model: model,
                    isFocused: true,
                    fixedHeight: nil,
                    onOpen: { onOpen(model.id) },
                    onShop: { onShop(model.id) }
                )
            }
        }
    }
}
