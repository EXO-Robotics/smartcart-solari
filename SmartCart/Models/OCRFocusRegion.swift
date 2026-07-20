import CoreGraphics
import Foundation

/// One axis-aligned OCR focus rectangle in normalized, top-left image coordinates.
/// The original image remains authoritative; this value only scopes OCR work.
struct OCRFocusRegion: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let fullImage = OCRFocusRegion(
        x: 0,
        y: 0,
        width: 1,
        height: 1
    )

    var isFullImage: Bool {
        abs(x) < 0.0001
            && abs(y) < 0.0001
            && abs(width - 1) < 0.0001
            && abs(height - 1) < 0.0001
    }

    var isFiniteAndPositive: Bool {
        x.isFinite && y.isFinite && width.isFinite && height.isFinite
            && width > 0 && height > 0
    }

    func normalized(minimumDimension: Double = 0.08) -> OCRFocusRegion {
        guard isFiniteAndPositive else { return .fullImage }
        let minimum = min(1, max(0.01, minimumDimension))
        let resolvedWidth = min(1, max(minimum, width))
        let resolvedHeight = min(1, max(minimum, height))
        return OCRFocusRegion(
            x: min(max(0, x), 1 - resolvedWidth),
            y: min(max(0, y), 1 - resolvedHeight),
            width: resolvedWidth,
            height: resolvedHeight
        )
    }

    func movedBy(x deltaX: Double, y deltaY: Double) -> OCRFocusRegion {
        let region = normalized()
        return OCRFocusRegion(
            x: min(max(0, region.x + deltaX), 1 - region.width),
            y: min(max(0, region.y + deltaY), 1 - region.height),
            width: region.width,
            height: region.height
        )
    }

    func cropRect(for pixelSize: CGSize) -> CGRect {
        let region = normalized()
        return CGRect(
            x: region.x * pixelSize.width,
            y: region.y * pixelSize.height,
            width: region.width * pixelSize.width,
            height: region.height * pixelSize.height
        )
    }

    /// Converts a Vision-style bottom-left box from the focused crop back into
    /// the original full-image coordinate space.
    func remappingVisionBox(_ box: OCRNormalizedBoundingBox) -> OCRNormalizedBoundingBox {
        let region = normalized()
        let regionBottom = 1 - region.y - region.height
        return OCRNormalizedBoundingBox(
            x: region.x + (box.x * region.width),
            y: regionBottom + (box.y * region.height),
            width: box.width * region.width,
            height: box.height * region.height
        )
    }

    func remappingVisionRect(_ box: NormalizedSourceRect) -> NormalizedSourceRect {
        let remapped = remappingVisionBox(
            OCRNormalizedBoundingBox(
                x: box.x,
                y: box.y,
                width: box.width,
                height: box.height
            )
        )
        return NormalizedSourceRect(
            x: remapped.x,
            y: remapped.y,
            width: remapped.width,
            height: remapped.height
        )
    }
}
