import SwiftUI
import UIKit

struct IngredientFocusResult {
    var regions: [OCRFocusRegion]
}

struct IngredientFocusView: View {
    @Environment(\.dismiss) private var dismiss

    let images: [UIImage]
    let onCompletion: (IngredientFocusResult?) -> Void

    @State private var currentPage = 0
    @State private var regions: [OCRFocusRegion]
    @State private var suggestedRegions: [OCRFocusRegion]
    @State private var manuallyEditedPages: Set<Int> = []
    @State private var zoom: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var magnificationStart: CGFloat?
    @State private var panStart: CGSize?
    @State private var selectionDragStart: OCRFocusRegion?
    @State private var resizeDragStart: OCRFocusRegion?

    init(
        images: [UIImage],
        onCompletion: @escaping (IngredientFocusResult?) -> Void
    ) {
        self.images = images
        self.onCompletion = onCompletion
        let defaults = Array(repeating: OCRFocusRegion.fullImage, count: images.count)
        _regions = State(initialValue: defaults)
        _suggestedRegions = State(initialValue: defaults)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let image = currentImage {
                    imageViewer(image)
                    guidance
                } else {
                    ContentUnavailableView(
                        "Photo unavailable",
                        systemImage: "photo.badge.exclamationmark",
                        description: Text("Return and choose the recipe photo again.")
                    )
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Focus Ingredients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { complete(nil) }
                        .accessibilityIdentifier("ingredient-focus-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reset") { resetCurrentPage() }
                        .disabled(currentImage == nil)
                        .accessibilityIdentifier("ingredient-focus-reset")
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
        }
        .task {
            let suggestions = await OCRFocusRegionSuggester.suggestRegions(in: images)
            guard !Task.isCancelled else { return }
            for index in suggestions.indices where regions.indices.contains(index) {
                suggestedRegions[index] = suggestions[index]
                if !manuallyEditedPages.contains(index) {
                    regions[index] = suggestions[index]
                }
            }
        }
    }

    private var currentImage: UIImage? {
        images.indices.contains(currentPage) ? images[currentPage] : nil
    }

    private var currentRegion: OCRFocusRegion {
        guard regions.indices.contains(currentPage) else { return .fullImage }
        return regions[currentPage]
    }

    private func imageViewer(_ image: UIImage) -> some View {
        GeometryReader { geometry in
            let viewport = geometry.size
            let baseRect = fittedImageRect(for: image, in: viewport)
            let imageRect = transformedImageRect(baseRect, in: viewport)
            let selectionRect = displayRect(for: currentRegion, in: imageRect)

            ZStack {
                Color.black

                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: baseRect.width, height: baseRect.height)
                    .scaleEffect(zoom)
                    .offset(panOffset)

                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)
                    .gesture(panGesture(baseRect: baseRect, viewport: viewport))

                dimmingMask(imageRect: imageRect, selectionRect: selectionRect)
                    .allowsHitTesting(false)

                selectionOverlay(selectionRect, imageRect: imageRect)
            }
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(magnificationGesture(baseRect: baseRect, viewport: viewport))
            .accessibilityIdentifier("ingredient-focus-image-viewer")
        }
        .frame(maxHeight: .infinity)
    }

    private var guidance: some View {
        VStack(spacing: 9) {
            if images.count > 1 {
                HStack(spacing: 18) {
                    Button {
                        changePage(by: -1)
                    } label: {
                        Image(systemName: "chevron.left.circle.fill")
                    }
                    .disabled(currentPage == 0)

                    Text("Page \(currentPage + 1) of \(images.count)")
                        .font(.subheadline.weight(.semibold))

                    Button {
                        changePage(by: 1)
                    } label: {
                        Image(systemName: "chevron.right.circle.fill")
                    }
                    .disabled(currentPage == images.count - 1)
                }
                .font(.title3)
                .accessibilityIdentifier("ingredient-focus-page-indicator")
            }

            Text("Pinch to zoom · Drag or resize the box")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            Button {
                setCurrentRegion(.fullImage)
            } label: {
                Label("Use Full Photo", systemImage: "photo.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("ingredient-focus-full-photo")

            Button {
                complete(IngredientFocusResult(regions: regions.map { $0.normalized() }))
            } label: {
                Label("Scan Ingredients", systemImage: "text.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(images.isEmpty)
            .accessibilityIdentifier("ingredient-focus-scan")
            .accessibilityHint("Scans the selected area on every recipe page")
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private func selectionOverlay(_ rect: CGRect, imageRect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.white, lineWidth: 2)
                .background(Color.white.opacity(0.001))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .contentShape(Rectangle())
                .gesture(moveSelectionGesture(imageRect: imageRect))
                .accessibilityLabel("Ingredient focus selection")
                .accessibilityHint("Drag to reposition the ingredient focus area")

            Text("Ingredients")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.white)
                .clipShape(Capsule())
                .position(x: min(rect.maxX - 40, rect.minX + 42), y: max(13, rect.minY + 14))
                .allowsHitTesting(false)

            ForEach(FocusResizeHandle.allCases) { handle in
                resizeHandle(handle, selectionRect: rect, imageRect: imageRect)
            }
        }
    }

    private func resizeHandle(
        _ handle: FocusResizeHandle,
        selectionRect: CGRect,
        imageRect: CGRect
    ) -> some View {
        Circle()
            .fill(Color.white)
            .overlay { Circle().stroke(Color.black.opacity(0.35), lineWidth: 1) }
            .frame(width: handle.isCorner ? 16 : 13, height: handle.isCorner ? 16 : 13)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .position(handle.position(in: selectionRect))
            .gesture(resizeGesture(handle, imageRect: imageRect))
            .accessibilityLabel(handle.accessibilityLabel)
            .accessibilityHint("Drag to resize the ingredient focus area")
    }

    private func dimmingMask(imageRect: CGRect, selectionRect: CGRect) -> some View {
        Path { path in
            path.addRect(imageRect)
            path.addRect(selectionRect)
        }
        .fill(Color.black.opacity(0.56), style: FillStyle(eoFill: true))
    }

    private func moveSelectionGesture(imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if selectionDragStart == nil { selectionDragStart = currentRegion }
                guard let start = selectionDragStart,
                      imageRect.width > 0, imageRect.height > 0 else { return }
                setCurrentRegion(
                    start.movedBy(
                        x: value.translation.width / imageRect.width,
                        y: value.translation.height / imageRect.height
                    ),
                    markEdited: true
                )
            }
            .onEnded { _ in selectionDragStart = nil }
    }

    private func resizeGesture(
        _ handle: FocusResizeHandle,
        imageRect: CGRect
    ) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if resizeDragStart == nil { resizeDragStart = currentRegion }
                guard let start = resizeDragStart,
                      imageRect.width > 0, imageRect.height > 0 else { return }
                let dx = Double(value.translation.width / imageRect.width)
                let dy = Double(value.translation.height / imageRect.height)
                setCurrentRegion(
                    resized(start, handle: handle, dx: dx, dy: dy),
                    markEdited: true
                )
            }
            .onEnded { _ in resizeDragStart = nil }
    }

    private func panGesture(baseRect: CGRect, viewport: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if panStart == nil { panStart = panOffset }
                guard let start = panStart else { return }
                panOffset = clampedPan(
                    CGSize(
                        width: start.width + value.translation.width,
                        height: start.height + value.translation.height
                    ),
                    baseRect: baseRect,
                    viewport: viewport,
                    scale: zoom
                )
            }
            .onEnded { _ in panStart = nil }
    }

    private func magnificationGesture(baseRect: CGRect, viewport: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if magnificationStart == nil { magnificationStart = zoom }
                let start = magnificationStart ?? zoom
                zoom = min(5, max(1, start * value.magnification))
                panOffset = clampedPan(
                    panOffset,
                    baseRect: baseRect,
                    viewport: viewport,
                    scale: zoom
                )
            }
            .onEnded { _ in magnificationStart = nil }
    }

    private func resized(
        _ source: OCRFocusRegion,
        handle: FocusResizeHandle,
        dx: Double,
        dy: Double
    ) -> OCRFocusRegion {
        let minimum = 0.08
        var left = source.x
        var top = source.y
        var right = source.x + source.width
        var bottom = source.y + source.height

        if handle.movesLeft { left = min(max(0, left + dx), right - minimum) }
        if handle.movesRight { right = max(min(1, right + dx), left + minimum) }
        if handle.movesTop { top = min(max(0, top + dy), bottom - minimum) }
        if handle.movesBottom { bottom = max(min(1, bottom + dy), top + minimum) }

        return OCRFocusRegion(
            x: left,
            y: top,
            width: right - left,
            height: bottom - top
        ).normalized()
    }

    private func resetCurrentPage() {
        zoom = 1
        panOffset = .zero
        guard suggestedRegions.indices.contains(currentPage) else { return }
        setCurrentRegion(suggestedRegions[currentPage], markEdited: true)
    }

    private func setCurrentRegion(
        _ region: OCRFocusRegion,
        markEdited: Bool = true
    ) {
        guard regions.indices.contains(currentPage) else { return }
        regions[currentPage] = region.normalized()
        if markEdited { manuallyEditedPages.insert(currentPage) }
    }

    private func changePage(by delta: Int) {
        currentPage = min(max(0, currentPage + delta), max(0, images.count - 1))
        zoom = 1
        panOffset = .zero
        magnificationStart = nil
        panStart = nil
    }

    private func complete(_ result: IngredientFocusResult?) {
        dismiss()
        onCompletion(result)
    }

    private func fittedImageRect(for image: UIImage, in viewport: CGSize) -> CGRect {
        guard image.size.width > 0, image.size.height > 0,
              viewport.width > 0, viewport.height > 0 else { return .zero }
        let scale = min(viewport.width / image.size.width, viewport.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(
            x: (viewport.width - size.width) / 2,
            y: (viewport.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func transformedImageRect(_ baseRect: CGRect, in viewport: CGSize) -> CGRect {
        let size = CGSize(width: baseRect.width * zoom, height: baseRect.height * zoom)
        return CGRect(
            x: (viewport.width - size.width) / 2 + panOffset.width,
            y: (viewport.height - size.height) / 2 + panOffset.height,
            width: size.width,
            height: size.height
        )
    }

    private func displayRect(for region: OCRFocusRegion, in imageRect: CGRect) -> CGRect {
        let normalized = region.normalized()
        return CGRect(
            x: imageRect.minX + imageRect.width * normalized.x,
            y: imageRect.minY + imageRect.height * normalized.y,
            width: imageRect.width * normalized.width,
            height: imageRect.height * normalized.height
        )
    }

    private func clampedPan(
        _ proposed: CGSize,
        baseRect: CGRect,
        viewport: CGSize,
        scale: CGFloat
    ) -> CGSize {
        let horizontalLimit = max(0, ((baseRect.width * scale) - viewport.width) / 2)
        let verticalLimit = max(0, ((baseRect.height * scale) - viewport.height) / 2)
        return CGSize(
            width: min(max(-horizontalLimit, proposed.width), horizontalLimit),
            height: min(max(-verticalLimit, proposed.height), verticalLimit)
        )
    }
}

private enum FocusResizeHandle: String, CaseIterable, Identifiable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    var id: String { rawValue }

    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomRight, .bottomLeft: true
        default: false
        }
    }

    var movesLeft: Bool { self == .left || self == .topLeft || self == .bottomLeft }
    var movesRight: Bool { self == .right || self == .topRight || self == .bottomRight }
    var movesTop: Bool { self == .top || self == .topLeft || self == .topRight }
    var movesBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }

    var accessibilityLabel: String {
        rawValue
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .capitalized + " resize handle"
    }

    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        }
    }
}
