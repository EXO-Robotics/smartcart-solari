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

    func testCardUsesFullCarouselWidthWithoutExposingTheNextCard() {
        XCTAssertEqual(WeeklyMealCarouselLayout.cardWidth(containerWidth: 320), 320, accuracy: 0.01)
        XCTAssertEqual(WeeklyMealCarouselLayout.cardWidth(containerWidth: 440), 440, accuracy: 0.01)
    }

    func testDragIntentLeavesVerticalHomeScrollingAvailable() {
        XCTAssertEqual(
            WeeklyMealCarouselLayout.dragIntent(CGSize(width: 12, height: 90)),
            .vertical
        )
        XCTAssertEqual(
            WeeklyMealCarouselLayout.dragIntent(CGSize(width: 24, height: 24)),
            .undetermined
        )
        XCTAssertEqual(
            WeeklyMealCarouselLayout.dragIntent(CGSize(width: 90, height: 12)),
            .horizontal
        )
    }

    func testHomeOwnsRackGestureInsteadOfTheCardHierarchy() throws {
        let homeSource = try source("SmartCart/Features/Home/HomeView.swift")
        let carouselSource = try source(
            "SmartCart/WeeklyMeals/Features/WeeklyMealMagnifyingCarousel.swift"
        )

        XCTAssertTrue(homeSource.contains(".simultaneousGesture(homeWeeklyMealRackGesture, including: .gesture)"))
        XCTAssertTrue(homeSource.contains("coordinateSpace: .named(WeeklyMealRackCoordinateSpace.name)"))
        XCTAssertTrue(homeSource.contains("weeklyMealRackInteraction.frame = frame"))
        XCTAssertFalse(carouselSource.contains(".simultaneousGesture(rackDragGesture"))
        XCTAssertFalse(carouselSource.contains("DragGesture(minimumDistance: 8)"))
    }

    func testHomeShopActionUsesRecipeReadyEntryInsteadOfDetailNavigation() throws {
        let homeSource = try source("SmartCart/Features/Home/HomeView.swift")

        XCTAssertTrue(homeSource.contains("onShop: shopWeeklyMeal"))
        XCTAssertTrue(homeSource.contains("appModel.beginWeeklyMeal("))
        XCTAssertFalse(homeSource.contains("onShop: { appModel.continueTo(.weeklyMealDetail($0)) }"))
    }

    func testIncomingCardEmergesFromBehindFocusedCardWithRestrainedDepth() {
        let focused = WeeklyMealCarouselLayout.rackTransform(
            relativeIndex: 0,
            dragTranslation: -160,
            cardWidth: 320,
            reduceMotion: false
        )
        let incoming = WeeklyMealCarouselLayout.rackTransform(
            relativeIndex: 1,
            dragTranslation: -160,
            cardWidth: 320,
            reduceMotion: false
        )

        XCTAssertEqual(focused.horizontalOffset, -147.2, accuracy: 0.01)
        XCTAssertEqual(focused.scale, 0.9875, accuracy: 0.001)
        XCTAssertEqual(incoming.horizontalOffset, 160, accuracy: 0.01)
        XCTAssertEqual(incoming.scale, 0.97, accuracy: 0.001)
        XCTAssertEqual(incoming.opacity, 1, accuracy: 0.001)
        XCTAssertEqual(incoming.rotationDegrees, -3, accuracy: 0.001)
    }

    func testIncomingCardKeepsAnOpaqueFallbackBehindItsGlassMaterial() throws {
        let cardSource = try source("SmartCart/WeeklyMeals/Features/WeeklyMealCard.swift")

        XCTAssertTrue(cardSource.contains(".fill(SmartCartTheme.paper)"))
        XCTAssertTrue(cardSource.contains("SmartCartSmokedGlassSurface("))
    }

    func testReduceMotionRemovesRackDepthTransforms() {
        let transform = WeeklyMealCarouselLayout.rackTransform(
            relativeIndex: 1,
            dragTranslation: -160,
            cardWidth: 320,
            reduceMotion: true
        )

        XCTAssertEqual(transform.scale, 1, accuracy: 0.001)
        XCTAssertEqual(transform.verticalOffset, 0, accuracy: 0.001)
        XCTAssertEqual(transform.rotationDegrees, 0, accuracy: 0.001)
        XCTAssertEqual(transform.opacity, 1, accuracy: 0.001)
    }

    func testRackPagingUsesPredictedIntentAndStopsAtEnds() {
        XCTAssertEqual(
            WeeklyMealCarouselLayout.targetIndex(
                currentIndex: 3,
                translation: -30,
                predictedTranslation: -100,
                cardWidth: 320,
                count: 8
            ),
            4
        )
        XCTAssertEqual(
            WeeklyMealCarouselLayout.targetIndex(
                currentIndex: 0,
                translation: 120,
                predictedTranslation: 160,
                cardWidth: 320,
                count: 8
            ),
            0
        )
        XCTAssertEqual(
            WeeklyMealCarouselLayout.targetIndex(
                currentIndex: 7,
                translation: -120,
                predictedTranslation: -160,
                cardWidth: 320,
                count: 8
            ),
            7
        )
    }

    func testRackArrowAvailabilityMatchesCollectionEnds() {
        XCTAssertFalse(WeeklyMealCarouselLayout.canMoveBackward(from: 0))
        XCTAssertTrue(WeeklyMealCarouselLayout.canMoveForward(from: 0, count: 8))
        XCTAssertTrue(WeeklyMealCarouselLayout.canMoveBackward(from: 4))
        XCTAssertTrue(WeeklyMealCarouselLayout.canMoveForward(from: 4, count: 8))
        XCTAssertTrue(WeeklyMealCarouselLayout.canMoveBackward(from: 7))
        XCTAssertFalse(WeeklyMealCarouselLayout.canMoveForward(from: 7, count: 8))
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

    private func source(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
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
