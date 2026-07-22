import SwiftUI

struct WeeklyMealsSection: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var recordedView = false

    private let collection: ResolvedWeeklyMealCollection?
    private let models: [WeeklyMealDisplayModel]
    let interaction: WeeklyMealRackInteraction
    let onOpen: (CuratedRecipeID) -> Void
    let onShop: (CuratedRecipeID) -> Void
    let onSeeAll: () -> Void
    let onViewed: (String) -> Void
    let onFocused: (WeeklyMealDisplayModel) -> Void
    let onMealOpened: (WeeklyMealDisplayModel, String) -> Void

    init(
        interaction: WeeklyMealRackInteraction,
        onOpen: @escaping (CuratedRecipeID) -> Void,
        onShop: @escaping (CuratedRecipeID) -> Void,
        onSeeAll: @escaping () -> Void,
        onViewed: @escaping (String) -> Void,
        onFocused: @escaping (WeeklyMealDisplayModel) -> Void,
        onMealOpened: @escaping (WeeklyMealDisplayModel, String) -> Void
    ) {
        let resolved = try? BundledWeeklyMealRepository().activeCollection(
            on: Date(),
            calendar: Calendar.autoupdatingCurrent
        )
        collection = resolved
        models = resolved.map { WeeklyMealDisplayModelFactory.makeModels(from: $0) } ?? []
        self.interaction = interaction
        self.onOpen = onOpen
        self.onShop = onShop
        self.onSeeAll = onSeeAll
        self.onViewed = onViewed
        self.onFocused = onFocused
        self.onMealOpened = onMealOpened
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
                        interaction: interaction,
                        onOpen: { open($0, placement: "home_carousel") },
                        onShop: { open($0, placement: "home_carousel_shop") },
                        onFocused: onFocused
                    )
                }
            }
            .onAppear {
                if !recordedView {
                    recordedView = true
                    onViewed(collection.id)
                }
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
                    onOpen: { open(model.id, placement: "home_accessibility_list") },
                    onShop: { open(model.id, placement: "home_accessibility_list_shop") }
                )
            }
        }
    }

    private func open(_ id: CuratedRecipeID, placement: String) {
        guard let model = models.first(where: { $0.id == id }) else { return }
        onMealOpened(model, placement)
        if placement.hasSuffix("_shop") {
            onShop(id)
        } else {
            onOpen(id)
        }
    }
}
