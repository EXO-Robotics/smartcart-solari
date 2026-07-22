import Foundation
import XCTest
@testable import SmartCart

final class WeeklyMealCarouselTests: XCTestCase {
    func testDisplayModelsContainEightStableRecipesWithFeaturedFirst() throws {
        let collection = try repository.activeCollection(on: Date(timeIntervalSince1970: 0), calendar: calendar)
        let models = WeeklyMealDisplayModelFactory.makeModels(from: collection, locale: Locale(identifier: "en_US"))

        XCTAssertEqual(models.count, 8)
        XCTAssertEqual(models.first?.id.rawValue, "weekly.chicken-taco-rice-bowls")
        XCTAssertEqual(models.filter(\.isFeatured).count, 1)
        XCTAssertEqual(Set(models.map(\.id.rawValue)).count, 8)
    }

    func testProductionDisplayModelsHideUnverifiedCostWithoutZeroFallback() throws {
        let collection = try repository.activeCollection(on: Date(timeIntervalSince1970: 0), calendar: calendar)
        let models = WeeklyMealDisplayModelFactory.makeModels(from: collection, locale: Locale(identifier: "en_US"))

        XCTAssertTrue(models.allSatisfy { $0.costStatus == .requiresVerification })
        XCTAssertTrue(models.allSatisfy { $0.costPerServingText == nil })
    }

    func testCardWidthIsResponsiveAndCapped() {
        XCTAssertEqual(WeeklyMealCarouselLayout.cardWidth(containerWidth: 320), 268.8, accuracy: 0.01)
        XCTAssertEqual(WeeklyMealCarouselLayout.cardWidth(containerWidth: 440), 360, accuracy: 0.01)
    }

    func testFirstAndLastCardsReceiveFullCenteringMargin() {
        let width = WeeklyMealCarouselLayout.cardWidth(containerWidth: 320)
        XCTAssertEqual(
            WeeklyMealCarouselLayout.edgeMargin(containerWidth: 320, cardWidth: width),
            (320 - width) / 2,
            accuracy: 0.01
        )
    }

    func testMagnificationReducesAdjacentCardsWithoutEnlargingFocusedCard() {
        XCTAssertEqual(WeeklyMealCarouselLayout.scale(phase: 0), 1, accuracy: 0.001)
        XCTAssertEqual(WeeklyMealCarouselLayout.scale(phase: 1), 0.93, accuracy: 0.001)
        XCTAssertEqual(WeeklyMealCarouselLayout.verticalOffset(phase: 1), 7, accuracy: 0.001)
        XCTAssertEqual(WeeklyMealCarouselLayout.opacity(phase: 1, reduceMotion: false), 0.84, accuracy: 0.001)
        XCTAssertEqual(WeeklyMealCarouselLayout.opacity(phase: 1, reduceMotion: true), 0.90, accuracy: 0.001)
    }

    private var repository: BundledWeeklyMealRepository {
        get throws {
            try BundledWeeklyMealRepository(loader: TestWeeklyMealResourceLoader())
        }
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
}

private struct TestWeeklyMealResourceLoader: WeeklyMealsResourceLoading {
    func data(resource: String) throws -> Data {
        try Data(contentsOf: resourceDirectory.appendingPathComponent(resource))
    }

    private var resourceDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SmartCart/WeeklyMeals/Resources", isDirectory: true)
    }
}
