import UIKit
import UniformTypeIdentifiers

final class SmartCartShareViewController: UIViewController {
    private enum Copy {
        static let addAction = "Add to SmartCart"
        static let retryAction = "Try Again"
        #if DEBUG
        static let unsupportedOnly = "SmartCart can’t import this item. Share a public link, recipe text, or an image."
        #else
        static let unsupportedOnly = "SmartCart can’t import this item. Share recipe text or an image."
        #endif
        static let partialImport = "Some items couldn’t be added."
    }

    private let inbox = SmartCartShareInbox()
    private var preparedDraft: SmartCartShareDraft?
    private var loadTask: Task<Void, Never>?
    private var temporaryImageDirectory: URL?

    private let scrollView: UIScrollView = {
        let view = UIScrollView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alwaysBounceVertical = false
        view.showsVerticalScrollIndicator = false
        view.contentInsetAdjustmentBehavior = .never
        return view
    }()

    private lazy var buttonStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [cancelButton, addButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.distribution = .fillEqually
        stack.spacing = 10
        return stack
    }()

    private lazy var headingStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [markView, titleLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        return stack
    }()

    private lazy var statusStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [activityIndicator, statusLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        return stack
    }()

    private lazy var contentStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [headingStack, statusStack, buttonStack])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 22
        return stack
    }()

    private let markView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor(red: 0.14, green: 0.45, blue: 0.29, alpha: 1)
        view.layer.cornerRadius = 14
        return view
    }()

    private let markImageView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        let view = UIImageView(image: UIImage(systemName: "leaf.fill", withConfiguration: configuration))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tintColor = .white
        view.contentMode = .center
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Add to SmartCart"
        label.font = .preferredFont(forTextStyle: .title2)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor(red: 0.08, green: 0.13, blue: 0.20, alpha: 1)
        label.numberOfLines = 0
        return label
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Preparing your recipe…"
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .medium)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.color = UIColor(red: 0.14, green: 0.45, blue: 0.29, alpha: 1)
        view.hidesWhenStopped = true
        return view
    }()

    private lazy var cancelButton: UIButton = {
        var configuration = UIButton.Configuration.gray()
        configuration.title = "Cancel"
        configuration.cornerStyle = .large
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.textAlignment = .center
        button.addTarget(self, action: #selector(cancelSharing), for: .touchUpInside)
        return button
    }()

    private lazy var addButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = Copy.addAction
        configuration.baseBackgroundColor = UIColor(red: 0.14, green: 0.45, blue: 0.29, alpha: 1)
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .large
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.textAlignment = .center
        button.isEnabled = false
        button.addTarget(self, action: #selector(addToSmartCart), for: .touchUpInside)
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.97, green: 0.96, blue: 0.92, alpha: 1)
        configureLayout()
        updateLayoutForContentSizeCategory()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (viewController: SmartCartShareViewController, _) in
            viewController.updateLayoutForContentSizeCategory()
        }
        prepareSharedInput()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePreferredContentSize()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        loadTask?.cancel()
        cleanTemporaryImages()
    }

    private func configureLayout() {
        markView.addSubview(markImageView)
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            markView.widthAnchor.constraint(equalToConstant: 48),
            markView.heightAnchor.constraint(equalToConstant: 48),
            markImageView.centerXAnchor.constraint(equalTo: markView.centerXAnchor),
            markImageView.centerYAnchor.constraint(equalTo: markView.centerYAnchor),
            cancelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
            addButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
            scrollView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            contentStack.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor,
                constant: 8
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor,
                constant: -8
            ),
            contentStack.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor,
                constant: 24
            ),
            contentStack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor,
                constant: -20
            ),
            contentStack.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor,
                constant: -16
            )
        ])
    }

    private func updateLayoutForContentSizeCategory() {
        let usesAccessibilityLayout = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        headingStack.axis = usesAccessibilityLayout ? .vertical : .horizontal
        headingStack.alignment = usesAccessibilityLayout ? .leading : .center
        buttonStack.axis = usesAccessibilityLayout ? .vertical : .horizontal
        statusStack.axis = usesAccessibilityLayout ? .vertical : .horizontal
        statusStack.alignment = usesAccessibilityLayout ? .leading : .center
        view.setNeedsLayout()
    }

    private func updatePreferredContentSize() {
        let availableWidth = max(scrollView.bounds.width - 16, 1)
        guard availableWidth > 1 else { return }

        let fittingSize = contentStack.systemLayoutSizeFitting(
            CGSize(width: availableWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let desiredHeight = ceil(
            fittingSize.height
                + 44
                + view.safeAreaInsets.top
                + view.safeAreaInsets.bottom
        )
        let minimumHeight: CGFloat = 290
        let screenHeight = view.window?.windowScene?.screen.bounds.height ?? 700
        let maximumHeight = max(minimumHeight, floor(screenHeight * 0.8))
        let fittedHeight = min(max(desiredHeight, minimumHeight), maximumHeight)

        scrollView.isScrollEnabled = desiredHeight > fittedHeight
        guard abs(preferredContentSize.height - fittedHeight) > 0.5 else { return }
        preferredContentSize = CGSize(width: 0, height: fittedHeight)
    }

    private func prepareSharedInput() {
        loadTask?.cancel()
        cleanTemporaryImages()
        preparedDraft = nil
        addButton.isEnabled = false
        setPrimaryActionTitle(Copy.addAction)
        statusLabel.textColor = .secondaryLabel
        statusLabel.text = "Preparing your recipe…"
        activityIndicator.startAnimating()

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let draft = try await collectDraft()
                try Task.checkCancellation()
                preparedDraft = draft
                activityIndicator.stopAnimating()
                setPrimaryActionTitle(Copy.addAction)
                addButton.isEnabled = true
                let readySummary = summary(for: draft)
                statusLabel.text = readySummary
                announce("Ready. \(readySummary)")
            } catch is CancellationError {
                return
            } catch {
                cleanTemporaryImages()
                activityIndicator.stopAnimating()
                statusLabel.textColor = UIColor(red: 0.71, green: 0.20, blue: 0.18, alpha: 1)
                statusLabel.text = conciseMessage(for: error)
                setPrimaryActionTitle(Copy.retryAction)
                addButton.isEnabled = true
                announce("Couldn’t prepare recipe. \(conciseMessage(for: error))")
            }
        }
    }

    private func collectDraft() async throws -> SmartCartShareDraft {
        let extensionItems = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let providers = extensionItems.flatMap { $0.attachments ?? [] }
        guard !providers.isEmpty else { throw SmartCartShareInboxError.emptyImport }

        let imageProviderCount = providers.filter { provider in
            provider.registeredTypeIdentifiers.contains { UTType($0)?.conforms(to: .image) == true }
        }.count
        guard imageProviderCount <= SmartCartShareInbox.maximumImageCount else {
            throw SmartCartShareInboxError.tooManyImages(
                maximum: SmartCartShareInbox.maximumImageCount
            )
        }

        var publicURL: URL?
        var plainText: String?
        var images: [SmartCartSharedImageInput] = []
        var unsupportedAttachmentCount = 0

        for provider in providers {
            try Task.checkCancellation()
            let imageType = provider.registeredTypeIdentifiers.first(where: {
                UTType($0)?.conforms(to: .image) == true
            })
            #if DEBUG
            let hasURL = provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
            #else
            let hasURL = false
            #endif
            let hasPlainText = provider.hasItemConformingToTypeIdentifier(
                UTType.plainText.identifier
            )

            switch SmartCartShareInbox.preferredAttachment(
                hasImage: imageType != nil && images.count < SmartCartShareInbox.maximumImageCount,
                hasURL: hasURL && publicURL == nil,
                hasPlainText: hasPlainText && plainText == nil
            ) {
            case .image:
                guard let imageType else { continue }
                do {
                    images.append(try await loadImage(from: provider, typeIdentifier: imageType))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    unsupportedAttachmentCount += 1
                }
            case .publicURL:
                do {
                    guard let candidate = try await loadURL(from: provider),
                          SmartCartShareInbox.isPublicHTTPSURL(candidate) else {
                        unsupportedAttachmentCount += 1
                        continue
                    }
                    publicURL = candidate
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    unsupportedAttachmentCount += 1
                }
            case .plainText:
                do {
                    let candidate = try await loadText(from: provider)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if candidate?.isEmpty == false {
                        plainText = candidate
                    } else {
                        unsupportedAttachmentCount += 1
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    unsupportedAttachmentCount += 1
                }
            case .unsupported:
                unsupportedAttachmentCount += 1
            }
        }

        guard publicURL != nil || plainText != nil || !images.isEmpty else {
            if unsupportedAttachmentCount > 0 {
                throw SmartCartShareInboxError.unsupportedAttachment
            }
            throw SmartCartShareInboxError.emptyImport
        }

        return SmartCartShareDraft(
            publicURL: publicURL,
            plainText: plainText,
            images: images,
            unsupportedAttachmentCount: unsupportedAttachmentCount
        )
    }

    private func loadURL(from provider: NSItemProvider) async throws -> URL? {
        let item = try await loadItem(from: provider, typeIdentifier: UTType.url.identifier)
        if let url = item as? URL { return url }
        if let value = item as? String { return URL(string: value) }
        if let value = item as? NSString { return URL(string: value as String) }
        return nil
    }

    private func loadText(from provider: NSItemProvider) async throws -> String? {
        let item = try await loadItem(from: provider, typeIdentifier: UTType.plainText.identifier)
        if let value = item as? String { return value }
        if let value = item as? NSString { return value as String }
        if let data = item as? Data { return String(data: data, encoding: .utf8) }
        if let data = item as? NSData { return String(data: data as Data, encoding: .utf8) }
        return nil
    }

    private func loadItem(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> NSSecureCoding? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: item)
                }
            }
        }
    }

    private func loadImage(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> SmartCartSharedImageInput {
        let directory = try temporaryImageStagingDirectory()
        let fileExtension = UTType(typeIdentifier)?.preferredFilenameExtension
        let fileName = fileExtension.map { "\(UUID().uuidString).\($0)" } ?? UUID().uuidString
        let destination = directory.appendingPathComponent(fileName, isDirectory: false)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                do {
                    if let error { throw error }
                    guard let url else { throw SmartCartShareInboxError.emptyImage }
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        let values = try destination.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) > 0 else {
            throw SmartCartShareInboxError.emptyImage
        }
        return SmartCartSharedImageInput(
            fileURL: destination,
            typeIdentifier: typeIdentifier,
            preferredFilenameExtension: fileExtension
        )
    }

    private func temporaryImageStagingDirectory() throws -> URL {
        if let temporaryImageDirectory { return temporaryImageDirectory }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartCartShare-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryImageDirectory = directory
        return directory
    }

    private func cleanTemporaryImages() {
        guard let temporaryImageDirectory else { return }
        try? FileManager.default.removeItem(at: temporaryImageDirectory)
        self.temporaryImageDirectory = nil
    }

    private func summary(for draft: SmartCartShareDraft) -> String {
        var parts: [String] = []
        if !draft.images.isEmpty {
            parts.append("\(draft.images.count) recipe image\(draft.images.count == 1 ? "" : "s")")
        }
        if draft.publicURL != nil { parts.append("recipe link") }
        if draft.plainText != nil { parts.append("recipe text") }

        let joined = ListFormatter.localizedString(byJoining: parts)
        let base = "\(joined.capitalized) ready to add."
        if draft.unsupportedAttachmentCount > 0 {
            return "\(base) \(Copy.partialImport)"
        }
        return base
    }

    private func conciseMessage(for error: Error) -> String {
        guard let shareError = error as? SmartCartShareInboxError else {
            return "SmartCart couldn’t prepare this item. Try again."
        }
        if shareError == .unsupportedAttachment {
            return Copy.unsupportedOnly
        }
        if shareError == .containerUnavailable {
            return "SmartCart couldn’t save this item. Try again."
        }
        return shareError.localizedDescription
    }

    @objc private func addToSmartCart() {
        guard let preparedDraft else {
            prepareSharedInput()
            return
        }
        addButton.isEnabled = false
        cancelButton.isEnabled = false
        activityIndicator.startAnimating()
        statusLabel.textColor = .secondaryLabel
        statusLabel.text = "Saving on this iPhone…"

        do {
            try inbox.enqueue(preparedDraft)
            cleanTemporaryImages()
            activityIndicator.stopAnimating()
            statusLabel.text = "Ready in SmartCart."
            announce("Added to SmartCart.")
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            activityIndicator.stopAnimating()
            cancelButton.isEnabled = true
            addButton.isEnabled = true
            setPrimaryActionTitle(Copy.retryAction)
            statusLabel.textColor = UIColor(red: 0.71, green: 0.20, blue: 0.18, alpha: 1)
            statusLabel.text = conciseMessage(for: error)
            announce("Couldn’t save to SmartCart. \(conciseMessage(for: error))")
        }
    }

    private func setPrimaryActionTitle(_ title: String) {
        var configuration = addButton.configuration
        configuration?.title = title
        addButton.configuration = configuration
    }

    private func announce(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    @objc private func cancelSharing() {
        loadTask?.cancel()
        cleanTemporaryImages()
        extensionContext?.completeRequest(returningItems: nil)
    }
}
