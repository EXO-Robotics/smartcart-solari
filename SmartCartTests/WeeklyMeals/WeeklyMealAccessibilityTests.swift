import Foundation
import XCTest
@testable import SmartCart

final class WeeklyMealAccessibilityTests: XCTestCase {
    func testRecipeCardUsesAButtonTraitWithoutAFullCardButtonGesture() throws {
        let source = try String(contentsOf: weeklyMealCardSourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains(".onTapGesture(perform: onOpen)"))
        XCTAssertTrue(source.contains(".accessibilityAddTraits(.isButton)"))
        XCTAssertTrue(source.contains(".accessibilityAction(.default, onOpen)"))
        XCTAssertFalse(source.contains("Button(action: onOpen)"))
    }

    func testFeaturedCardProvidesOneCoherentEstimatedSummary() throws {
        let featured = try XCTUnwrap(models.first { $0.isFeatured })

        XCTAssertEqual(
            featured.accessibilitySummary,
            "Chicken Taco Rice Bowls. Featured lunch. Estimated 500 calories. 46 grams of protein. Serves 4. 35 minutes. High Protein and Meal Prep Friendly"
        )
    }

    func testUnverifiedCostIsNotAnnouncedAsZeroOrPending() throws {
        let models = try models
        for model in models {
            XCTAssertFalse(model.accessibilitySummary.contains("$0.00"))
            XCTAssertFalse(model.accessibilitySummary.localizedCaseInsensitiveContains("cost estimate pending"))
        }
    }

    func testEveryCardSummaryContainsTitleServingAndTime() throws {
        let models = try models
        XCTAssertEqual(models.count, 8)
        for model in models {
            XCTAssertTrue(model.accessibilitySummary.contains(model.title))
            XCTAssertTrue(model.accessibilitySummary.contains("Serves \(model.defaultServings)"))
            XCTAssertTrue(model.accessibilitySummary.contains("\(model.totalMinutes) minutes"))
        }
    }

    private var models: [WeeklyMealDisplayModel] {
        get throws {
            let directory = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("SmartCart/WeeklyMeals/Resources", isDirectory: true)
            let repository = try BundledWeeklyMealRepository(
                loader: AccessibilityResourceLoader(directory: directory)
            )
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let collection = try repository.activeCollection(
                on: Date(timeIntervalSince1970: 0),
                calendar: calendar
            )
            return WeeklyMealDisplayModelFactory.makeModels(from: collection)
        }
    }

    private var weeklyMealCardSourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SmartCart/WeeklyMeals/Features/WeeklyMealCard.swift")
    }
}

private struct AccessibilityResourceLoader: WeeklyMealsResourceLoading {
    let directory: URL
    func data(resource: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(resource))
    }
}
