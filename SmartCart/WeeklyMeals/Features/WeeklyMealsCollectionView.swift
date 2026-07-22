import SwiftUI

struct WeeklyMealsCollectionView: View {
    @Environment(AppModel.self) private var appModel

    private let models: [WeeklyMealDisplayModel]

    init() {
        let collection = try? BundledWeeklyMealRepository().activeCollection(
            on: Date(),
            calendar: Calendar.autoupdatingCurrent
        )
        models = collection.map { WeeklyMealDisplayModelFactory.makeModels(from: $0) } ?? []
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                ForEach(WeeklyMealSlot.allCases, id: \.self) { slot in
                    let meals = models.filter { $0.slot == slot }
                    if !meals.isEmpty {
                        Section {
                            ForEach(meals) { model in
                                WeeklyMealCollectionRow(model: model) {
                                    appModel.continueTo(.weeklyMealDetail(model.id))
                                }
                            }
                        } header: {
                            Label(slot.displayName, systemImage: slot.symbolName)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(SmartCartTheme.green)
                        }
                    }
                }
            }
            .padding(20)
        }
        .smartCartBackground()
        .navigationTitle("This Week’s Meals")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WeeklyMealCollectionRow: View {
    let model: WeeklyMealDisplayModel
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 13) {
                Image(systemName: model.slot.symbolName)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(SmartCartTheme.green.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(SmartCartTheme.ink)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(SmartCartTheme.secondaryInk)
                        .lineLimit(2)
                }
                Spacer(minLength: 5)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(SmartCartTheme.mutedInk)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(SmartCartTheme.paper.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens recipe details")
    }

    private var summary: String {
        var values: [String] = []
        if let calories = model.caloriesPerServing { values.append("Est. \(calories) cal") }
        if let protein = model.proteinGramsPerServing { values.append("Est. \(protein.formatted()) g protein") }
        values.append("\(model.totalMinutes) min")
        values.append("Serves \(model.defaultServings)")
        return values.joined(separator: " · ")
    }
}
