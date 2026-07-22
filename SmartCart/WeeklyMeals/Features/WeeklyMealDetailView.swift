import SwiftUI

struct WeeklyMealDetailView: View {
    let recipeID: CuratedRecipeID

    private let meal: ResolvedWeeklyMeal?

    init(recipeID: CuratedRecipeID) {
        self.recipeID = recipeID
        let collection = try? BundledWeeklyMealRepository().activeCollection(
            on: Date(),
            calendar: Calendar.autoupdatingCurrent
        )
        meal = collection?.meals.first { $0.recipe.id == recipeID }
    }

    var body: some View {
        Group {
            if let meal {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Label(meal.entry.slot.displayName, systemImage: meal.entry.slot.symbolName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(SmartCartTheme.green)
                        Text(meal.recipe.title)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(SmartCartTheme.ink)
                        Text(meal.recipe.shortDescription)
                            .font(.body)
                            .foregroundStyle(SmartCartTheme.secondaryInk)
                        Text("Recipe shopping options are below.")
                            .font(.footnote)
                            .foregroundStyle(SmartCartTheme.mutedInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
            } else {
                ContentUnavailableView(
                    "Meal unavailable",
                    systemImage: "fork.knife",
                    description: Text("This bundled meal could not be loaded.")
                )
            }
        }
        .smartCartBackground()
        .navigationTitle("Weekly Meal")
        .navigationBarTitleDisplayMode(.inline)
    }
}
