import Darwin
import Foundation

/// Immutable metadata handed from the Share extension to the main app.
/// Image bytes remain as separate files beside the envelope.
struct SmartCartShareEnvelope: Codable, Equatable, Identifiable, Sendable {
    struct Image: Codable, Equatable, Identifiable, Sendable {
        let id: UUID
        let fileName: String
        let typeIdentifier: String?
    }

    let id: UUID
    let createdAt: Date
    let publicURL: URL?
    let plainText: String?
    let images: [Image]
    let unsupportedAttachmentCount: Int
}

struct SmartCartSharedImageInput: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case data(Data)
        case file(URL)
    }

    let source: Source
    let typeIdentifier: String?
    let preferredFilenameExtension: String?

    init(
        data: Data,
        typeIdentifier: String?,
        preferredFilenameExtension: String?
    ) {
        source = .data(data)
        self.typeIdentifier = typeIdentifier
        self.preferredFilenameExtension = preferredFilenameExtension
    }

    init(
        fileURL: URL,
        typeIdentifier: String?,
        preferredFilenameExtension: String?
    ) {
        source = .file(fileURL)
        self.typeIdentifier = typeIdentifier
        self.preferredFilenameExtension = preferredFilenameExtension
    }
}

struct SmartCartShareDraft: Equatable, Sendable {
    let publicURL: URL?
    let plainText: String?
    let images: [SmartCartSharedImageInput]
    let unsupportedAttachmentCount: Int

    init(
        publicURL: URL? = nil,
        plainText: String? = nil,
        images: [SmartCartSharedImageInput] = [],
        unsupportedAttachmentCount: Int = 0
    ) {
        // One envelope carries one deterministic import path. Safari often
        // supplies a URL plus descriptive text, and Photos may supply several
        // representations; choosing once here prevents acknowledged payloads
        // from being silently stranded behind a higher-priority attachment.
        if !images.isEmpty {
            self.publicURL = nil
            self.plainText = nil
            self.images = images
        } else if publicURL != nil {
            self.publicURL = publicURL
            self.plainText = nil
            self.images = []
        } else {
            self.publicURL = nil
            self.plainText = plainText
            self.images = []
        }
        self.unsupportedAttachmentCount = max(0, unsupportedAttachmentCount)
    }
}

enum SmartCartShareInboxError: LocalizedError, Equatable {
    case containerUnavailable
    case emptyImport
    case unsupportedAttachment
    case invalidPublicURL
    case tooManyImages(maximum: Int)
    case emptyImage
    case unsafeImageName
    case entryNotFound
    case duplicateEntry

    var errorDescription: String? {
        switch self {
        case .containerUnavailable:
            "SmartCart couldn't access its shared recipe inbox. Try again after opening SmartCart."
        case .emptyImport:
            "Share a public link, recipe text, or at least one image."
        case .unsupportedAttachment:
            "SmartCart can import a public link, recipe text, or recipe images."
        case .invalidPublicURL:
            "SmartCart can import only public HTTPS recipe links from the Share sheet."
        case .tooManyImages(let maximum):
            "Choose no more than \(maximum) recipe images."
        case .emptyImage:
            "One of the shared images could not be read."
        case .unsafeImageName:
            "A shared image had an unsafe file name."
        case .entryNotFound:
            "That shared recipe is no longer in the inbox."
        case .duplicateEntry:
            "That shared recipe is already in the inbox."
        }
    }
}

/// Cross-process inbox with one publication boundary: a directory rename from
/// staging to ready. A read never claims an entry. Acknowledgement atomically
/// moves it out of ready before best-effort cleanup.
struct SmartCartShareInbox: @unchecked Sendable {
    enum AttachmentPreference: Equatable, Sendable {
        case image
        case publicURL
        case plainText
        case unsupported
    }

    static let appGroupIdentifier = "group.com.blakestudio.smartcart"
    static let recipeBackendBundleKey = "SmartCartRecipeBackendURL"
    static let maximumImageCount = 8

    /// Mixed shares always use the same priority. Runtime URL capability is a
    /// consumption concern and must never cause the extension to drop a URL.
    static func preferredAttachment(
        hasImage: Bool,
        hasURL: Bool,
        hasPlainText: Bool
    ) -> AttachmentPreference {
        if hasImage { return .image }
        if hasURL { return .publicURL }
        if hasPlainText { return .plainText }
        return .unsupported
    }

    private static let rootDirectoryName = "SmartCartShareInbox"
    private static let stagingDirectoryName = "staging"
    private static let readyDirectoryName = "ready"
    private static let consumedDirectoryName = "consumed"
    private static let quarantineDirectoryName = "quarantine"
    private static let envelopeFileName = "envelope.json"
    private static let imagesDirectoryName = "images"

    private let fileManager: FileManager
    private let containerURLProvider: @Sendable () -> URL?
    private let consumedEntryCleanup: (@Sendable (URL) -> Void)?

    init(
        fileManager: FileManager = .default,
        containerURLProvider: @escaping @Sendable () -> URL? = {
            FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: SmartCartShareInbox.appGroupIdentifier
            )
        },
        consumedEntryCleanup: (@Sendable (URL) -> Void)? = nil
    ) {
        self.fileManager = fileManager
        self.containerURLProvider = containerURLProvider
        self.consumedEntryCleanup = consumedEntryCleanup
    }

    /// Test and preview initializer that never depends on code signing.
    init(
        fileManager: FileManager = .default,
        containerURL: URL?,
        consumedEntryCleanup: (@Sendable (URL) -> Void)? = nil
    ) {
        self.init(
            fileManager: fileManager,
            containerURLProvider: { containerURL },
            consumedEntryCleanup: consumedEntryCleanup
        )
    }

    @discardableResult
    func enqueue(
        _ draft: SmartCartShareDraft,
        id: UUID = UUID(),
        createdAt: Date = .now
    ) throws -> SmartCartShareEnvelope {
        let normalizedText = draft.plainText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let plainText = normalizedText?.isEmpty == false ? normalizedText : nil

        let publicURL: URL?
        if let candidate = draft.publicURL {
            guard Self.isPublicHTTPSURL(candidate) else {
                throw SmartCartShareInboxError.invalidPublicURL
            }
            publicURL = candidate
        } else {
            publicURL = nil
        }

        guard draft.images.count <= Self.maximumImageCount else {
            throw SmartCartShareInboxError.tooManyImages(maximum: Self.maximumImageCount)
        }
        guard try draft.images.allSatisfy({ try hasReadableBytes($0.source) }) else {
            throw SmartCartShareInboxError.emptyImage
        }

        let hasSupportedInput = publicURL != nil || plainText != nil || !draft.images.isEmpty
        guard hasSupportedInput else {
            if draft.unsupportedAttachmentCount > 0 {
                throw SmartCartShareInboxError.unsupportedAttachment
            }
            throw SmartCartShareInboxError.emptyImport
        }

        let directories = try inboxDirectories(createIfNeeded: true)
        let entryName = id.uuidString
        let stagingURL = directories.staging.appendingPathComponent(entryName, isDirectory: true)
        let readyURL = directories.ready.appendingPathComponent(entryName, isDirectory: true)
        let consumedURL = directories.consumed.appendingPathComponent(entryName, isDirectory: true)
        guard !fileManager.fileExists(atPath: stagingURL.path),
              !fileManager.fileExists(atPath: readyURL.path),
              !fileManager.fileExists(atPath: consumedURL.path) else {
            throw SmartCartShareInboxError.duplicateEntry
        }

        var ownsStagingDirectory = false
        do {
            do {
                try fileManager.createDirectory(
                    at: stagingURL,
                    withIntermediateDirectories: false
                )
                ownsStagingDirectory = true
            } catch {
                if fileManager.fileExists(atPath: stagingURL.path) {
                    throw SmartCartShareInboxError.duplicateEntry
                }
                throw error
            }

            let imagesURL = stagingURL.appendingPathComponent(Self.imagesDirectoryName, isDirectory: true)
            if !draft.images.isEmpty {
                try fileManager.createDirectory(at: imagesURL, withIntermediateDirectories: false)
            }

            var imageRecords: [SmartCartShareEnvelope.Image] = []
            imageRecords.reserveCapacity(draft.images.count)
            for input in draft.images {
                let imageID = UUID()
                let fileExtension = Self.safeFilenameExtension(input.preferredFilenameExtension)
                let fileName = fileExtension.map { "\(imageID.uuidString).\($0)" }
                    ?? imageID.uuidString
                let destination = imagesURL.appendingPathComponent(fileName, isDirectory: false)
                switch input.source {
                case .data(let data):
                    try data.write(to: destination, options: .atomic)
                case .file(let sourceURL):
                    try fileManager.copyItem(at: sourceURL, to: destination)
                }
                imageRecords.append(
                    SmartCartShareEnvelope.Image(
                        id: imageID,
                        fileName: fileName,
                        typeIdentifier: input.typeIdentifier
                    )
                )
            }

            let durableCreatedAt = Date(
                timeIntervalSince1970: floor(createdAt.timeIntervalSince1970 * 1_000) / 1_000
            )
            let envelope = SmartCartShareEnvelope(
                id: id,
                createdAt: durableCreatedAt,
                publicURL: publicURL,
                plainText: plainText,
                images: imageRecords,
                unsupportedAttachmentCount: draft.unsupportedAttachmentCount
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(envelope).write(
                to: stagingURL.appendingPathComponent(Self.envelopeFileName),
                options: .atomic
            )

            do {
                try fileManager.moveItem(at: stagingURL, to: readyURL)
                ownsStagingDirectory = false
            } catch {
                if fileManager.fileExists(atPath: readyURL.path)
                    || fileManager.fileExists(atPath: consumedURL.path) {
                    throw SmartCartShareInboxError.duplicateEntry
                }
                throw error
            }
            return envelope
        } catch {
            if ownsStagingDirectory {
                try? fileManager.removeItem(at: stagingURL)
            }
            throw error
        }
    }

    /// Returns the oldest valid entry without claiming it. Invalid or replayed
    /// entries are quarantined so they cannot strand later valid work.
    func oldestReady() throws -> SmartCartShareEnvelope? {
        let directories = try inboxDirectories(createIfNeeded: true)
        let entryURLs = try fileManager.contentsOfDirectory(
            at: directories.ready,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var valid: [SmartCartShareEnvelope] = []
        for entryURL in entryURLs {
            do {
                let consumedURL = directories.consumed.appendingPathComponent(
                    entryURL.lastPathComponent,
                    isDirectory: true
                )
                guard !fileManager.fileExists(atPath: consumedURL.path) else {
                    throw SmartCartShareInboxError.duplicateEntry
                }
                valid.append(try decodeAndValidateEntry(at: entryURL))
            } catch {
                try? quarantine(entryURL, in: directories.quarantine)
            }
        }

        return valid.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }.first
    }

    func imageData(
        for image: SmartCartShareEnvelope.Image,
        in envelope: SmartCartShareEnvelope
    ) throws -> Data {
        guard envelope.images.contains(image), Self.isSafeLeafName(image.fileName) else {
            throw SmartCartShareInboxError.unsafeImageName
        }
        let directories = try inboxDirectories(createIfNeeded: false)
        let imageURL = directories.ready
            .appendingPathComponent(envelope.id.uuidString, isDirectory: true)
            .appendingPathComponent(Self.imagesDirectoryName, isDirectory: true)
            .appendingPathComponent(image.fileName, isDirectory: false)
        guard fileManager.fileExists(atPath: imageURL.path) else {
            throw SmartCartShareInboxError.entryNotFound
        }
        return try Data(contentsOf: imageURL, options: [.mappedIfSafe])
    }

    /// Moves the immutable entry out of the visible queue before cleanup.
    /// Cleanup is deliberately best-effort: once moved, a failure cannot replay
    /// an already accepted or explicitly discarded import.
    @discardableResult
    func acknowledge(_ id: UUID) throws -> Bool {
        let directories = try inboxDirectories(createIfNeeded: false)
        let entryName = id.uuidString
        let readyURL = directories.ready.appendingPathComponent(entryName, isDirectory: true)
        let consumedURL = directories.consumed.appendingPathComponent(entryName, isDirectory: true)
        guard fileManager.fileExists(atPath: readyURL.path) else { return false }
        guard !fileManager.fileExists(atPath: consumedURL.path) else {
            throw SmartCartShareInboxError.duplicateEntry
        }
        try fileManager.moveItem(at: readyURL, to: consumedURL)
        if let consumedEntryCleanup {
            consumedEntryCleanup(consumedURL)
        } else {
            try? fileManager.removeItem(at: consumedURL)
        }
        return true
    }

    @discardableResult
    func discard(_ id: UUID) throws -> Bool {
        try acknowledge(id)
    }

    private func decodeAndValidateEntry(at entryURL: URL) throws -> SmartCartShareEnvelope {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: entryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let data = try Data(
            contentsOf: entryURL.appendingPathComponent(Self.envelopeFileName),
            options: [.mappedIfSafe]
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let envelope = try decoder.decode(SmartCartShareEnvelope.self, from: data)
        let trimmedText = envelope.plainText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard entryURL.lastPathComponent == envelope.id.uuidString,
              envelope.images.count <= Self.maximumImageCount,
              envelope.unsupportedAttachmentCount >= 0,
              envelope.publicURL.map(Self.isPublicHTTPSURL) ?? true,
              envelope.publicURL != nil || trimmedText?.isEmpty == false || !envelope.images.isEmpty,
              Set(envelope.images.map(\.id)).count == envelope.images.count,
              Set(envelope.images.map(\.fileName)).count == envelope.images.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for image in envelope.images {
            guard Self.isSafeLeafName(image.fileName) else {
                throw SmartCartShareInboxError.unsafeImageName
            }
            let imageURL = entryURL
                .appendingPathComponent(Self.imagesDirectoryName, isDirectory: true)
                .appendingPathComponent(image.fileName, isDirectory: false)
            var imageIsDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: imageURL.path, isDirectory: &imageIsDirectory),
                  !imageIsDirectory.boolValue,
                  try imageURL.resourceValues(forKeys: [.fileSizeKey]).fileSize.map({ $0 > 0 }) == true else {
                throw SmartCartShareInboxError.entryNotFound
            }
        }
        return envelope
    }

    private func quarantine(_ entryURL: URL, in quarantineURL: URL) throws {
        let destination = quarantineURL.appendingPathComponent(
            "\(entryURL.lastPathComponent)-\(UUID().uuidString)",
            isDirectory: entryURL.hasDirectoryPath
        )
        try fileManager.moveItem(at: entryURL, to: destination)
    }

    private func hasReadableBytes(_ source: SmartCartSharedImageInput.Source) throws -> Bool {
        switch source {
        case .data(let data):
            return !data.isEmpty
        case .file(let url):
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            return values.isRegularFile == true && (values.fileSize ?? 0) > 0
        }
    }

    private func inboxDirectories(createIfNeeded: Bool) throws -> (
        staging: URL,
        ready: URL,
        consumed: URL,
        quarantine: URL
    ) {
        guard let containerURL = containerURLProvider() else {
            throw SmartCartShareInboxError.containerUnavailable
        }
        let root = containerURL.appendingPathComponent(Self.rootDirectoryName, isDirectory: true)
        let staging = root.appendingPathComponent(Self.stagingDirectoryName, isDirectory: true)
        let ready = root.appendingPathComponent(Self.readyDirectoryName, isDirectory: true)
        let consumed = root.appendingPathComponent(Self.consumedDirectoryName, isDirectory: true)
        let quarantine = root.appendingPathComponent(Self.quarantineDirectoryName, isDirectory: true)
        if createIfNeeded {
            for directory in [root, staging, ready, consumed, quarantine] {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
        return (staging, ready, consumed, quarantine)
    }

    private static func safeFilenameExtension(_ candidate: String?) -> String? {
        guard let candidate else { return nil }
        let lowered = candidate.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let allowed = CharacterSet.alphanumerics
        guard !lowered.isEmpty,
              lowered.count <= 10,
              lowered.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return lowered
    }

    private static func isSafeLeafName(_ value: String) -> Bool {
        value == URL(fileURLWithPath: value).lastPathComponent
            && !value.contains("..")
            && !value.isEmpty
    }

    static func isPublicHTTPSURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              let rawHost = url.host?.lowercased(),
              let host = normalizedHost(rawHost),
              !host.isEmpty else { return false }

        if host.contains(":") {
            guard let bytes = ipv6Bytes(host) else { return false }
            return isPublicIPv6(bytes)
        }

        if host.unicodeScalars.allSatisfy({
            CharacterSet(charactersIn: "0123456789.").contains($0)
        }) {
            guard let octets = strictIPv4Octets(host) else { return false }
            return isPublicIPv4(octets)
        }

        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        if components.allSatisfy({ component in
            component.allSatisfy(\.isNumber)
                || (component.lowercased().hasPrefix("0x")
                    && component.dropFirst(2).allSatisfy(\.isHexDigit))
        }) {
            return false
        }
        return !isReservedDNSHost(host)
    }

    /// Reports whether the main app may safely attempt URL extraction. This
    /// never participates in enqueueing, so an unavailable Release capability
    /// leaves the URL durable and retryable.
    static func recipeLinkImportIsConfigured(
        bundleInfo: [String: Any] = Bundle.main.infoDictionary ?? [:],
        allowsLocalDebugBackend: Bool = {
            #if DEBUG
            true
            #else
            false
            #endif
        }()
    ) -> Bool {
        guard let rawValue = bundleInfo[recipeBackendBundleKey] as? String else {
            return false
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.contains("$("),
              let url = URL(string: value),
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil else { return false }

        if allowsLocalDebugBackend {
            let scheme = url.scheme?.lowercased()
            return (scheme == "http" || scheme == "https") && url.host?.isEmpty == false
        }
        return isPublicHTTPSURL(url)
    }

    private static func normalizedHost(_ rawHost: String) -> String? {
        var host = rawHost
        if host.hasPrefix("[") && host.hasSuffix("]") {
            host.removeFirst()
            host.removeLast()
        }
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty,
              !host.contains("%"),
              host.unicodeScalars.allSatisfy({ !$0.properties.isWhitespace }) else {
            return nil
        }
        return host
    }

    private static func strictIPv4Octets(_ host: String) -> [UInt8]? {
        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4 else { return nil }
        var octets: [UInt8] = []
        octets.reserveCapacity(4)
        for component in components {
            guard !component.isEmpty,
                  component.allSatisfy(\.isNumber),
                  component == "0" || !component.hasPrefix("0"),
                  let value = UInt8(component) else { return nil }
            octets.append(value)
        }
        return octets
    }

    private static func isPublicIPv4(_ octets: [UInt8]) -> Bool {
        guard octets.count == 4 else { return false }
        let first = octets[0]
        let second = octets[1]
        let third = octets[2]

        if first == 0 || first == 10 || first == 127 || first >= 224 { return false }
        if first == 100, (64...127).contains(second) { return false }
        if first == 169, second == 254 { return false }
        if first == 172, (16...31).contains(second) { return false }
        if first == 192 {
            if second == 0, third == 0 || third == 2 { return false }
            if second == 31, third == 196 { return false }
            if second == 52, third == 193 { return false }
            if second == 88, third == 99 { return false }
            if second == 168 { return false }
            if second == 175, third == 48 { return false }
        }
        if first == 198, second == 18 || second == 19 { return false }
        if first == 198, second == 51, third == 100 { return false }
        if first == 203, second == 0, third == 113 { return false }
        return true
    }

    private static func ipv6Bytes(_ host: String) -> [UInt8]? {
        var address = in6_addr()
        let parsed = host.withCString { pointer in
            inet_pton(AF_INET6, pointer, &address)
        }
        guard parsed == 1 else { return nil }
        return withUnsafeBytes(of: &address) { Array($0) }
    }

    private static func isPublicIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return false }
        if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 0xFF, bytes[11] == 0xFF {
            return false
        }
        guard bytes[0] & 0xE0 == 0x20 else { return false }
        if bytes[0] == 0x20, bytes[1] == 0x01, bytes[2] <= 0x01 { return false }
        if bytes[0] == 0x20, bytes[1] == 0x01, bytes[2] == 0x0D, bytes[3] == 0xB8 {
            return false
        }
        if bytes[0] == 0x20, bytes[1] == 0x02 { return false }
        if bytes[0] == 0x3F, bytes[1] == 0xFF, bytes[2] & 0xF0 == 0 { return false }
        return true
    }

    private static func isReservedDNSHost(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return true }

        let reservedExactNames: Set<String> = ["example.com", "example.net", "example.org"]
        if reservedExactNames.contains(host) { return true }
        if reservedExactNames.contains(where: { host.hasSuffix(".\($0)") }) { return true }

        let reservedSuffixes = [
            ".alt", ".arpa", ".example", ".home", ".internal", ".invalid",
            ".lan", ".local", ".localdomain", ".localhost", ".onion", ".test"
        ]
        return reservedSuffixes.contains { host.hasSuffix($0) }
    }
}
