import Foundation
import XCTest
@testable import SmartCart

final class SmartCartShareInboxTests: XCTestCase {
    func testReleaseShareExtensionDoesNotAdvertiseUnavailableRecipeURLImport() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let releaseURL = repositoryRoot.appendingPathComponent(
            "SmartCartShareExtension/Info-Release.plist"
        )
        let data = try Data(contentsOf: releaseURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let extensionDictionary = try XCTUnwrap(plist["NSExtension"] as? [String: Any])
        let attributes = try XCTUnwrap(
            extensionDictionary["NSExtensionAttributes"] as? [String: Any]
        )
        let activation = try XCTUnwrap(
            attributes["NSExtensionActivationRule"] as? [String: Any]
        )

        XCTAssertNil(activation["NSExtensionActivationSupportsWebURLWithMaxCount"])
        XCTAssertEqual(activation["NSExtensionActivationSupportsText"] as? Bool, true)
        XCTAssertEqual(activation["NSExtensionActivationSupportsImageWithMaxCount"] as? Int, 8)
    }

    func testMixedAttachmentPolicyIsDeterministicAndCapabilityIndependent() {
        XCTAssertEqual(
            SmartCartShareInbox.preferredAttachment(
                hasImage: true,
                hasURL: true,
                hasPlainText: true
            ),
            .image
        )
        XCTAssertEqual(
            SmartCartShareInbox.preferredAttachment(
                hasImage: false,
                hasURL: true,
                hasPlainText: true
            ),
            .publicURL
        )
        XCTAssertEqual(
            SmartCartShareInbox.preferredAttachment(
                hasImage: false,
                hasURL: false,
                hasPlainText: true
            ),
            .plainText
        )
        XCTAssertEqual(
            SmartCartShareInbox.preferredAttachment(
                hasImage: false,
                hasURL: false,
                hasPlainText: false
            ),
            .unsupported
        )
    }

    func testMixedDraftCanonicalizesToOneWinningImportPath() throws {
        let url = try XCTUnwrap(URL(string: "https://www.apple.com/recipes/stew"))
        let image = SmartCartSharedImageInput(
            data: Data([0x01]),
            typeIdentifier: "public.jpeg",
            preferredFilenameExtension: "jpg"
        )

        let imageWinner = SmartCartShareDraft(
            publicURL: url,
            plainText: "lower priority text",
            images: [image]
        )
        XCTAssertEqual(imageWinner.images, [image])
        XCTAssertNil(imageWinner.publicURL)
        XCTAssertNil(imageWinner.plainText)

        let urlWinner = SmartCartShareDraft(
            publicURL: url,
            plainText: "lower priority text"
        )
        XCTAssertEqual(urlWinner.publicURL, url)
        XCTAssertNil(urlWinner.plainText)
        XCTAssertTrue(urlWinner.images.isEmpty)
    }

    func testURLRoundTripsWhenReleaseRecipeCapabilityIsHidden() throws {
        let container = try temporaryContainer()
        let originalInbox = SmartCartShareInbox(containerURL: container)
        let url = try XCTUnwrap(URL(string: "https://www.apple.com/recipes/soup"))
        let id = UUID()

        XCTAssertFalse(
            SmartCartShareInbox.recipeLinkImportIsConfigured(
                bundleInfo: [:],
                allowsLocalDebugBackend: false
            )
        )
        try originalInbox.enqueue(SmartCartShareDraft(publicURL: url), id: id)

        let relaunchedInbox = SmartCartShareInbox(containerURL: container)
        let decoded = try XCTUnwrap(relaunchedInbox.oldestReady())
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.publicURL, url)
        XCTAssertNil(decoded.plainText)
        XCTAssertTrue(decoded.images.isEmpty)
    }

    func testHiddenRecipeLinkCapabilityRetainsURLWithoutTreatingItAsIngredientText() {
        let hidden = RecipeComposerInitialInput(
            requestedMethod: .recipeLink,
            initialText: "  https://www.apple.com/recipes/soup  ",
            recipeLinkCapability: .unavailable(.missing)
        )

        XCTAssertEqual(hidden.visibleMethod, .recipeText)
        XCTAssertEqual(hidden.linkText, "https://www.apple.com/recipes/soup")
        XCTAssertEqual(hidden.recipeText, "")
        XCTAssertEqual(
            hidden.fallbackMessage,
            RecipeLinkCapability.unavailable(.missing).fallbackMessage
        )

        let available = RecipeComposerInitialInput(
            requestedMethod: .recipeLink,
            initialText: " https://www.apple.com/recipes/soup ",
            recipeLinkCapability: .available
        )
        XCTAssertEqual(available.visibleMethod, .recipeLink)
        XCTAssertEqual(available.linkText, "https://www.apple.com/recipes/soup")
        XCTAssertEqual(available.recipeText, "")
        XCTAssertNil(available.fallbackMessage)

        let pastedText = RecipeComposerInitialInput(
            requestedMethod: .recipeText,
            initialText: "  2 eggs\n1 cup flour  ",
            recipeLinkCapability: .unavailable(.missing)
        )
        XCTAssertEqual(pastedText.visibleMethod, .recipeText)
        XCTAssertEqual(pastedText.linkText, "")
        XCTAssertEqual(pastedText.recipeText, "2 eggs\n1 cup flour")
        XCTAssertNil(pastedText.fallbackMessage)
    }

    func testTextRoundTripsWithNormalizedWhitespace() throws {
        let container = try temporaryContainer()
        let id = UUID()
        try SmartCartShareInbox(containerURL: container).enqueue(
            SmartCartShareDraft(plainText: "  2 eggs\n1 cup flour  \n"),
            id: id
        )

        let decoded = try XCTUnwrap(SmartCartShareInbox(containerURL: container).oldestReady())
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.plainText, "2 eggs\n1 cup flour")
        XCTAssertNil(decoded.publicURL)
    }

    func testSingleImageRoundTripsMetadataAndBytes() throws {
        let container = try temporaryContainer()
        let inbox = SmartCartShareInbox(containerURL: container)
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        try inbox.enqueue(
            SmartCartShareDraft(
                images: [
                    SmartCartSharedImageInput(
                        data: bytes,
                        typeIdentifier: "public.png",
                        preferredFilenameExtension: "PNG"
                    )
                ]
            )
        )

        let decoded = try XCTUnwrap(inbox.oldestReady())
        let image = try XCTUnwrap(decoded.images.first)
        XCTAssertEqual(decoded.images.count, 1)
        XCTAssertEqual(image.typeIdentifier, "public.png")
        XCTAssertTrue(image.fileName.hasSuffix(".png"))
        XCTAssertEqual(try inbox.imageData(for: image, in: decoded), bytes)
    }

    func testMultipleImagesRoundTripInSubmittedOrder() throws {
        let container = try temporaryContainer()
        let inbox = SmartCartShareInbox(containerURL: container)
        let expected = (1...8).map { Data([UInt8($0), UInt8($0 + 10)]) }
        let inputs = expected.enumerated().map { index, bytes in
            SmartCartSharedImageInput(
                data: bytes,
                typeIdentifier: "public.jpeg",
                preferredFilenameExtension: index.isMultiple(of: 2) ? "jpg" : "jpeg"
            )
        }
        try inbox.enqueue(SmartCartShareDraft(images: inputs))

        let decoded = try XCTUnwrap(inbox.oldestReady())
        XCTAssertEqual(decoded.images.count, expected.count)
        let actual = try decoded.images.map { try inbox.imageData(for: $0, in: decoded) }
        XCTAssertEqual(actual, expected)
    }

    func testFileBackedImageSurvivesSourceDeletion() throws {
        let container = try temporaryContainer()
        let sourceContainer = try temporaryContainer()
        let sourceURL = sourceContainer.appendingPathComponent("recipe.heic")
        let bytes = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70])
        try bytes.write(to: sourceURL, options: .atomic)
        let inbox = SmartCartShareInbox(containerURL: container)
        try inbox.enqueue(
            SmartCartShareDraft(
                images: [
                    SmartCartSharedImageInput(
                        fileURL: sourceURL,
                        typeIdentifier: "public.heic",
                        preferredFilenameExtension: "heic"
                    )
                ]
            )
        )
        try FileManager.default.removeItem(at: sourceURL)

        let decoded = try XCTUnwrap(inbox.oldestReady())
        XCTAssertEqual(
            try inbox.imageData(for: try XCTUnwrap(decoded.images.first), in: decoded),
            bytes
        )
    }

    func testUnsupportedOnlyIsTypedWhileSupportedInputIsPreserved() throws {
        let unsupportedOnly = SmartCartShareInbox(containerURL: try temporaryContainer())
        XCTAssertThrowsError(
            try unsupportedOnly.enqueue(SmartCartShareDraft(unsupportedAttachmentCount: 2))
        ) { error in
            XCTAssertEqual(error as? SmartCartShareInboxError, .unsupportedAttachment)
        }

        let container = try temporaryContainer()
        let mixedInbox = SmartCartShareInbox(containerURL: container)
        try mixedInbox.enqueue(
            SmartCartShareDraft(
                plainText: "1 cup oats",
                unsupportedAttachmentCount: 3
            )
        )
        let decoded = try XCTUnwrap(mixedInbox.oldestReady())
        XCTAssertEqual(decoded.plainText, "1 cup oats")
        XCTAssertEqual(decoded.unsupportedAttachmentCount, 3)
    }

    func testDuplicateEnvelopeIdentityNeverOverwritesReadyOrConsumedEntry() throws {
        let container = try temporaryContainer()
        let id = UUID()
        let retainingInbox = SmartCartShareInbox(
            containerURL: container,
            consumedEntryCleanup: { _ in }
        )
        try retainingInbox.enqueue(SmartCartShareDraft(plainText: "first"), id: id)

        XCTAssertThrowsError(
            try retainingInbox.enqueue(SmartCartShareDraft(plainText: "second"), id: id)
        ) { error in
            XCTAssertEqual(error as? SmartCartShareInboxError, .duplicateEntry)
        }
        XCTAssertEqual(try retainingInbox.oldestReady()?.plainText, "first")

        XCTAssertTrue(try retainingInbox.acknowledge(id))
        XCTAssertThrowsError(
            try retainingInbox.enqueue(SmartCartShareDraft(plainText: "third"), id: id)
        ) { error in
            XCTAssertEqual(error as? SmartCartShareInboxError, .duplicateEntry)
        }
        XCTAssertNil(try retainingInbox.oldestReady())
    }

    func testPublicationIsAtomicAndOldestReadyOrderIsStable() throws {
        let container = try temporaryContainer()
        let inbox = SmartCartShareInbox(containerURL: container)
        let lexicallyFirst = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000101")
        )
        let lexicallySecond = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000102")
        )
        try inbox.enqueue(
            SmartCartShareDraft(plainText: "second"),
            id: lexicallySecond,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try inbox.enqueue(
            SmartCartShareDraft(plainText: "first"),
            id: lexicallyFirst,
            createdAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(try inbox.oldestReady()?.id, lexicallyFirst)
        let staging = container.appendingPathComponent(
            "SmartCartShareInbox/staging",
            isDirectory: true
        )
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: staging.path), [])
    }

    func testReadAndImportFailureRetainEntryUntilDurableAcknowledgement() throws {
        let container = try temporaryContainer()
        let id = UUID()
        try SmartCartShareInbox(containerURL: container).enqueue(
            SmartCartShareDraft(plainText: "retry me"),
            id: id
        )

        let firstProcess = SmartCartShareInbox(containerURL: container)
        XCTAssertEqual(try firstProcess.oldestReady()?.id, id)
        // Simulated importer failure: no acknowledgement is issued.
        XCTAssertEqual(try firstProcess.oldestReady()?.id, id)

        let relaunchedProcess = SmartCartShareInbox(containerURL: container)
        XCTAssertEqual(try relaunchedProcess.oldestReady()?.id, id)
        XCTAssertTrue(try relaunchedProcess.acknowledge(id))
        XCTAssertNil(try SmartCartShareInbox(containerURL: container).oldestReady())
    }

    func testAcknowledgementExcludesEntryEvenWhenConsumedCleanupIsRetained() throws {
        let container = try temporaryContainer()
        let id = UUID()
        let inbox = SmartCartShareInbox(
            containerURL: container,
            consumedEntryCleanup: { _ in }
        )
        try inbox.enqueue(SmartCartShareDraft(plainText: "durably accepted"), id: id)

        XCTAssertTrue(try inbox.acknowledge(id))
        XCTAssertNil(try inbox.oldestReady())
        XCTAssertNil(try SmartCartShareInbox(containerURL: container).oldestReady())

        let consumed = container
            .appendingPathComponent("SmartCartShareInbox/consumed", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: consumed.path))
    }

    func testDiscardIsExplicitAndRemovesEntryFromReadyQueue() throws {
        let container = try temporaryContainer()
        let inbox = SmartCartShareInbox(containerURL: container)
        let id = UUID()
        try inbox.enqueue(SmartCartShareDraft(plainText: "discard me"), id: id)

        XCTAssertEqual(try inbox.oldestReady()?.id, id)
        XCTAssertTrue(try inbox.discard(id))
        XCTAssertNil(try inbox.oldestReady())
        XCTAssertFalse(try inbox.discard(id))
    }

    func testMalformedEntryIsQuarantinedWithoutBlockingValidEntry() throws {
        let container = try temporaryContainer()
        let inbox = SmartCartShareInbox(containerURL: container)
        let validID = UUID()
        try inbox.enqueue(
            SmartCartShareDraft(plainText: "valid"),
            id: validID,
            createdAt: Date(timeIntervalSince1970: 200)
        )

        let malformedID = UUID()
        let malformedDirectory = container
            .appendingPathComponent("SmartCartShareInbox/ready", isDirectory: true)
            .appendingPathComponent(malformedID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: malformedDirectory,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(
            to: malformedDirectory.appendingPathComponent("envelope.json"),
            options: .atomic
        )

        XCTAssertEqual(try inbox.oldestReady()?.id, validID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: malformedDirectory.path))
        let quarantine = container.appendingPathComponent(
            "SmartCartShareInbox/quarantine",
            isDirectory: true
        )
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: quarantine.path).count, 1)
    }

    func testAppGroupUnavailableFailsSafelyForAllMutatingPrimitives() {
        let inbox = SmartCartShareInbox(containerURL: nil)
        XCTAssertThrowsError(
            try inbox.enqueue(SmartCartShareDraft(plainText: "2 eggs"))
        ) { error in
            XCTAssertEqual(error as? SmartCartShareInboxError, .containerUnavailable)
        }
        XCTAssertThrowsError(try inbox.oldestReady()) { error in
            XCTAssertEqual(error as? SmartCartShareInboxError, .containerUnavailable)
        }
        XCTAssertThrowsError(try inbox.acknowledge(UUID())) { error in
            XCTAssertEqual(error as? SmartCartShareInboxError, .containerUnavailable)
        }
        XCTAssertThrowsError(try inbox.discard(UUID())) { error in
            XCTAssertEqual(error as? SmartCartShareInboxError, .containerUnavailable)
        }
    }

    func testInvalidOrOversizedInputPublishesNoPartialEntry() throws {
        let container = try temporaryContainer()
        let inbox = SmartCartShareInbox(containerURL: container)
        let images = (0...8).map { value in
            SmartCartSharedImageInput(
                data: Data([UInt8(value)]),
                typeIdentifier: "public.jpeg",
                preferredFilenameExtension: "jpg"
            )
        }
        XCTAssertThrowsError(try inbox.enqueue(SmartCartShareDraft(images: images))) { error in
            XCTAssertEqual(
                error as? SmartCartShareInboxError,
                .tooManyImages(maximum: SmartCartShareInbox.maximumImageCount)
            )
        }
        XCTAssertNil(try inbox.oldestReady())

        XCTAssertThrowsError(
            try inbox.enqueue(
                SmartCartShareDraft(
                    images: [
                        SmartCartSharedImageInput(
                            data: Data(),
                            typeIdentifier: "public.png",
                            preferredFilenameExtension: "png"
                        )
                    ]
                )
            )
        ) { error in
            XCTAssertEqual(error as? SmartCartShareInboxError, .emptyImage)
        }
        XCTAssertNil(try inbox.oldestReady())
    }

    func testPublicURLValidationRejectsReservedNamesAndNonPublicLiteralForms() throws {
        let rejected = [
            "http://www.apple.com/recipe",
            "https://cook:secret@www.apple.com/recipe",
            "https://localhost/recipe",
            "https://kitchen.local/recipe",
            "https://router.internal/recipe",
            "https://smartcart.test/recipe",
            "https://www.example.com/recipe",
            "https://home.arpa/recipe",
            "https://single-label/recipe",
            "https://0.0.0.1/recipe",
            "https://10.0.0.1/recipe",
            "https://127.0.0.1/recipe",
            "https://0177.0.0.1/recipe",
            "https://2130706433/recipe",
            "https://0x7f000001/recipe",
            "https://169.254.10.20/recipe",
            "https://172.31.255.255/recipe",
            "https://192.168.1.1/recipe",
            "https://198.18.0.1/recipe",
            "https://203.0.113.1/recipe",
            "https://224.0.0.1/recipe",
            "https://[::1]/recipe",
            "https://[::ffff:8.8.8.8]/recipe",
            "https://[64:ff9b::808:808]/recipe",
            "https://[2001:db8::1]/recipe",
            "https://[fe80::1]/recipe",
            "https://[fc00::1]/recipe"
        ]
        for value in rejected {
            XCTAssertFalse(
                SmartCartShareInbox.isPublicHTTPSURL(try XCTUnwrap(URL(string: value))),
                value
            )
        }

        let accepted = [
            "https://recipes.smartcart.app/recipe",
            "https://www.apple.com/recipe",
            "https://8.8.8.8/recipe",
            "https://1.1.1.1/recipe",
            "https://[2606:4700:4700::1111]/recipe"
        ]
        for value in accepted {
            XCTAssertTrue(
                SmartCartShareInbox.isPublicHTTPSURL(try XCTUnwrap(URL(string: value))),
                value
            )
        }
    }

    func testEnqueueRejectsInvalidPublicURLBeforeCreatingInboxState() throws {
        let container = try temporaryContainer()
        let inbox = SmartCartShareInbox(containerURL: container)
        XCTAssertThrowsError(
            try inbox.enqueue(
                SmartCartShareDraft(
                    publicURL: try XCTUnwrap(URL(string: "https://www.example.com/recipe"))
                )
            )
        ) { error in
            XCTAssertEqual(error as? SmartCartShareInboxError, .invalidPublicURL)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: container.appendingPathComponent("SmartCartShareInbox").path
            )
        )
    }

    @MainActor
    func testColdLaunchPresentsOldestSharedImport() throws {
        let container = try temporaryContainer()
        let inbox = SmartCartShareInbox(containerURL: container)
        let olderID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000301")
        )
        let newerID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000302")
        )
        try inbox.enqueue(
            SmartCartShareDraft(plainText: "newer recipe"),
            id: newerID,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        try inbox.enqueue(
            SmartCartShareDraft(plainText: "older recipe"),
            id: olderID,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let model = try appModel(
            stateStore: ShareInboxIntegrationStateStore(),
            shareInbox: inbox
        )

        XCTAssertNil(model.pendingSharedImport)
        XCTAssertNil(model.presentedSheet)
        model.applicationDidBecomeActive()

        XCTAssertEqual(model.pendingSharedImport?.id, olderID)
        guard case let .importer(method, initialText) = model.presentedSheet else {
            return XCTFail("Cold activation should present the oldest shared recipe")
        }
        XCTAssertEqual(method, .recipeText)
        XCTAssertEqual(initialText, "older recipe")
        XCTAssertEqual(try inbox.oldestReady()?.id, olderID)
    }

    @MainActor
    func testWarmActivationDefersBehindExistingSheetThenPresentsAfterDismissal() throws {
        let container = try temporaryContainer()
        let inbox = SmartCartShareInbox(containerURL: container)
        let envelope = try inbox.enqueue(SmartCartShareDraft(plainText: "warm share"))
        let model = try appModel(
            stateStore: ShareInboxIntegrationStateStore(),
            shareInbox: inbox
        )
        model.presentedSheet = .importer(.camera)

        model.applicationDidBecomeActive()

        XCTAssertNil(model.pendingSharedImport)
        guard case let .importer(blockingMethod, _) = model.presentedSheet else {
            return XCTFail("The existing sheet should remain presented")
        }
        XCTAssertEqual(blockingMethod, .camera)

        model.presentedSheet = nil
        model.recipeImporterDidDismiss()

        XCTAssertEqual(model.pendingSharedImport?.id, envelope.id)
        guard case let .importer(method, initialText) = model.presentedSheet else {
            return XCTFail("The deferred share should present after the existing sheet dismisses")
        }
        XCTAssertEqual(method, .recipeText)
        XCTAssertEqual(initialText, "warm share")
    }

    @MainActor
    func testRepeatedActivationKeepsOnePendingPresentationAndDoesNotAdvanceQueue() throws {
        let container = try temporaryContainer()
        let inbox = SmartCartShareInbox(containerURL: container)
        let first = try inbox.enqueue(
            SmartCartShareDraft(plainText: "first share"),
            createdAt: Date(timeIntervalSince1970: 100)
        )
        _ = try inbox.enqueue(
            SmartCartShareDraft(plainText: "second share"),
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let model = try appModel(
            stateStore: ShareInboxIntegrationStateStore(),
            shareInbox: inbox
        )

        model.applicationDidBecomeActive()
        model.applicationDidBecomeActive()
        model.applicationDidBecomeActive()

        XCTAssertEqual(model.pendingSharedImport?.id, first.id)
        guard case let .importer(method, initialText) = model.presentedSheet else {
            return XCTFail("Repeated activation should retain one importer presentation")
        }
        XCTAssertEqual(method, .recipeText)
        XCTAssertEqual(initialText, "first share")
        XCTAssertEqual(try inbox.oldestReady()?.id, first.id)
    }

    @MainActor
    func testSuccessfulSharedRecipeSaveAcknowledgesAfterDurableCommitAndDoesNotRelaunch() throws {
        let container = try temporaryContainer()
        let inbox = SmartCartShareInbox(containerURL: container)
        let envelope = try inbox.enqueue(SmartCartShareDraft(plainText: "2 eggs"))
        let store = ShareInboxIntegrationStateStore()
        var readyEntryIDsObservedDuringSaves: [UUID?] = []
        store.beforeSuccessfulSave = {
            readyEntryIDsObservedDuringSaves.append(try? inbox.oldestReady()?.id)
        }
        let defaults = try isolatedDefaults()
        let model = try appModel(
            stateStore: store,
            shareInbox: inbox,
            commerceDefaults: defaults
        )
        model.applicationDidBecomeActive()

        XCTAssertTrue(
            model.beginSharedRecipe(
                sharedRecipe(title: "Shared omelet"),
                acknowledgingSharedImportID: envelope.id
            )
        )

        XCTAssertEqual(readyEntryIDsObservedDuringSaves.first, envelope.id)
        XCTAssertEqual(store.state?.recipes.filter { $0.id == envelope.id }.count, 1)
        XCTAssertNil(try inbox.oldestReady())
        XCTAssertNil(model.pendingSharedImport)

        let relaunched = try appModel(
            stateStore: store,
            shareInbox: SmartCartShareInbox(containerURL: container),
            commerceDefaults: defaults
        )
        relaunched.applicationDidBecomeActive()
        XCTAssertNil(relaunched.pendingSharedImport)
        XCTAssertNil(relaunched.presentedSheet)
        XCTAssertEqual(relaunched.recipes.filter { $0.id == envelope.id }.count, 1)
    }

    @MainActor
    func testFailedSharedRecipeSaveLeavesInboxEntryReadyForRetry() throws {
        let container = try temporaryContainer()
        let inbox = SmartCartShareInbox(containerURL: container)
        let envelope = try inbox.enqueue(SmartCartShareDraft(plainText: "2 eggs"))
        let store = ShareInboxIntegrationStateStore()
        store.failNextSave = true
        let model = try appModel(stateStore: store, shareInbox: inbox)
        model.applicationDidBecomeActive()

        XCTAssertFalse(
            model.beginSharedRecipe(
                sharedRecipe(title: "Unsaved omelet"),
                acknowledgingSharedImportID: envelope.id
            )
        )

        XCTAssertNil(store.state)
        XCTAssertEqual(model.pendingSharedImport?.id, envelope.id)
        XCTAssertEqual(try inbox.oldestReady()?.id, envelope.id)
        XCTAssertNotNil(model.sharedImportIssue)

        let retryModel = try appModel(
            stateStore: store,
            shareInbox: SmartCartShareInbox(containerURL: container)
        )
        retryModel.applicationDidBecomeActive()
        XCTAssertEqual(retryModel.pendingSharedImport?.id, envelope.id)
    }

    @MainActor
    func testRelaunchAcknowledgesRetainedInboxForDurableSameIDRecipeWithoutDuplication() throws {
        let container = try temporaryContainer()
        let inbox = SmartCartShareInbox(containerURL: container)
        let envelope = try inbox.enqueue(SmartCartShareDraft(plainText: "retained share"))
        let store = ShareInboxIntegrationStateStore()
        let defaults = try isolatedDefaults()

        let firstProcess = try appModel(
            stateStore: store,
            shareInbox: inbox,
            commerceDefaults: defaults
        )
        XCTAssertTrue(
            firstProcess.beginRecipe(
                sharedRecipe(id: envelope.id, title: "Already durable")
            )
        )
        XCTAssertEqual(store.state?.recipes.filter { $0.id == envelope.id }.count, 1)
        XCTAssertEqual(try inbox.oldestReady()?.id, envelope.id)

        let relaunched = try appModel(
            stateStore: store,
            shareInbox: SmartCartShareInbox(containerURL: container),
            commerceDefaults: defaults
        )
        relaunched.applicationDidBecomeActive()
        XCTAssertEqual(relaunched.pendingSharedImport?.id, envelope.id)

        XCTAssertTrue(
            relaunched.beginSharedRecipe(
                sharedRecipe(title: "Duplicate parser result"),
                acknowledgingSharedImportID: envelope.id
            )
        )

        XCTAssertNil(try inbox.oldestReady())
        XCTAssertNil(relaunched.pendingSharedImport)
        XCTAssertEqual(relaunched.recipes.filter { $0.id == envelope.id }.count, 1)
        XCTAssertEqual(relaunched.activeRecipe.id, envelope.id)
        XCTAssertEqual(relaunched.activeRecipe.title, "Already durable")
        XCTAssertEqual(store.state?.recipes.filter { $0.id == envelope.id }.count, 1)
    }

    @MainActor
    private func appModel(
        stateStore: any SmartCartStateStoring,
        shareInbox: SmartCartShareInbox,
        commerceDefaults: UserDefaults? = nil
    ) throws -> AppModel {
        let observerURL = try temporaryContainer().appendingPathComponent("operations.json")
        let observer = AsyncLocalOperationObserver(
            recorder: LocalOperationRecorder(fileURL: observerURL)
        )
        return AppModel(
            stateStore: stateStore,
            commerceDefaults: try commerceDefaults ?? isolatedDefaults(),
            shareInbox: shareInbox,
            operationObserver: observer
        )
    }

    private func sharedRecipe(
        id: UUID = UUID(),
        title: String
    ) -> Recipe {
        Recipe(
            id: id,
            title: title,
            source: .text,
            sourceDetail: "Share inbox integration test",
            heroSymbol: "fork.knife",
            servings: 2,
            prepMinutes: 5,
            cookMinutes: 5,
            ingredients: [Ingredient(name: "Eggs", quantity: 2, unit: "count")]
        )
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let name = "SmartCartShareInboxTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
        }
        return defaults
    }

    private func temporaryContainer() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SmartCartShareInboxTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

private final class ShareInboxIntegrationStateStore: SmartCartStateStoring {
    enum Failure: Error { case requested }

    var state: SmartCartPersistedState?
    var failNextSave = false
    var beforeSuccessfulSave: (() -> Void)?

    func load() throws -> SmartCartPersistedState? { state }

    func save(_ state: SmartCartPersistedState) throws {
        if failNextSave {
            failNextSave = false
            throw Failure.requested
        }
        beforeSuccessfulSave?()
        self.state = state
    }
}
