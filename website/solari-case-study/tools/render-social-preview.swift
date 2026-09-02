#!/usr/bin/env swift

import AppKit
import Foundation

let canvasSize = NSSize(width: 1200, height: 630)
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let backgroundURL = root.appendingPathComponent("SmartCart/Assets.xcassets/SmartCartHomeBackground.imageset/smartcart-home-food-background.png")
let iconURL = root.appendingPathComponent("SmartCart/Assets.xcassets/AppIcon.appiconset/SmartCart-AppIcon-1024.png")
let outputURL = root.appendingPathComponent("website/solari-case-study/assets/social-preview.jpg")

guard let background = NSImage(contentsOf: backgroundURL),
      let icon = NSImage(contentsOf: iconURL),
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize.width),
        pixelsHigh: Int(canvasSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      ) else {
  fatalError("Could not load SmartCart artwork or allocate the output canvas.")
}

bitmap.size = canvasSize
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let fullRect = NSRect(origin: .zero, size: canvasSize)
NSColor(calibratedRed: 0.018, green: 0.027, blue: 0.022, alpha: 1).setFill()
fullRect.fill()

// Preserve the app's real food photography while reframing it for a landscape card.
let sourceRect = NSRect(x: 0, y: 600, width: 853, height: 448)
background.draw(in: fullRect, from: sourceRect, operation: .sourceOver, fraction: 0.76)

let shade = NSGradient(colorsAndLocations:
  (NSColor(calibratedWhite: 0.01, alpha: 0.97), 0.0),
  (NSColor(calibratedWhite: 0.01, alpha: 0.77), 0.48),
  (NSColor(calibratedWhite: 0.01, alpha: 0.24), 1.0)
)!
shade.draw(in: fullRect, angle: 0)

let topWash = NSGradient(starting: NSColor(calibratedWhite: 0.0, alpha: 0.08),
                         ending: NSColor(calibratedWhite: 0.0, alpha: 0.48))!
topWash.draw(in: fullRect, angle: -90)

let amber = NSColor(calibratedRed: 1.0, green: 0.69, blue: 0.08, alpha: 1)
let ivory = NSColor(calibratedRed: 0.97, green: 0.96, blue: 0.91, alpha: 1)

// A quiet Solari signal line gives the card energy without turning it into a tech diagram.
amber.withAlphaComponent(0.82).setFill()
NSBezierPath(roundedRect: NSRect(x: 82, y: 550, width: 66, height: 7), xRadius: 3.5, yRadius: 3.5).fill()

func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, tracking: CGFloat = 0) {
  let style = NSMutableParagraphStyle()
  style.lineBreakMode = .byWordWrapping
  style.alignment = .left
  let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: color,
    .kern: tracking,
    .paragraphStyle: style
  ]
  NSAttributedString(string: text, attributes: attributes).draw(in: rect)
}

drawText("SMARTCART  ×  SOLARI",
         in: NSRect(x: 171, y: 518, width: 600, height: 60),
         font: NSFont.monospacedSystemFont(ofSize: 42, weight: .semibold),
         color: ivory,
         tracking: 0.8)

drawText("From Recipe To",
         in: NSRect(x: 80, y: 342, width: 700, height: 116),
         font: NSFont.systemFont(ofSize: 92, weight: .bold),
         color: ivory,
         tracking: -2.2)

drawText("Priced Basket.",
         in: NSRect(x: 80, y: 230, width: 700, height: 116),
         font: NSFont.systemFont(ofSize: 92, weight: .bold),
         color: amber,
         tracking: -2.2)

// Use the shipping icon exactly as-is. The amber frame visually connects it to Solari.
let iconFrame = NSRect(x: 775, y: 82, width: 430, height: 430)
let haloRect = iconFrame.insetBy(dx: -24, dy: -24)
let halo = NSGradient(starting: amber.withAlphaComponent(0.28), ending: amber.withAlphaComponent(0.0))!
halo.draw(in: NSBezierPath(ovalIn: haloRect), relativeCenterPosition: .zero)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.72)
shadow.shadowBlurRadius = 34
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()

let clipPath = NSBezierPath(roundedRect: iconFrame, xRadius: 86, yRadius: 86)
clipPath.addClip()
icon.draw(in: iconFrame, from: .zero, operation: .sourceOver, fraction: 1)

NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

amber.withAlphaComponent(0.88).setStroke()
let border = NSBezierPath(roundedRect: iconFrame.insetBy(dx: -2, dy: -2), xRadius: 88, yRadius: 88)
border.lineWidth = 3
border.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.93]) else {
  fatalError("Could not encode the social preview.")
}
try jpeg.write(to: outputURL)
print("Rendered \(outputURL.path) at 1200×630.")
