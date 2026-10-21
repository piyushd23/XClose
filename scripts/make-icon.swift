// Generates XClose's icons from Resources/Branding/AppIcon-source.png:
//   Resources/Bundle/AppIcon.icns          app icon, fitted to the macOS icon grid
//   Resources/Bundle/MenuBarIcon[@2x].png  monochrome template glyph of the star
// Usage: swift scripts/make-icon.swift <repo-root>
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("Resources/Branding/AppIcon-source.png")
let bundleDir = root.appendingPathComponent("Resources/Bundle")
guard let source = NSBitmapImageRep(data: try Data(contentsOf: sourceURL)), let sourceImage = source.cgImage else {
    fatalError("Cannot read \(sourceURL.path)")
}
let width = source.pixelsWide, height = source.pixelsHigh

/// Bounding box (in top-left pixel coordinates) of pixels matching `include`.
func bounds(_ include: (NSColor) -> Bool) -> CGRect {
    var minX = width, minY = height, maxX = 0, maxY = 0
    for y in stride(from: 0, to: height, by: 2) {
        for x in stride(from: 0, to: width, by: 2) where include(source.colorAt(x: x, y: y)!) {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    return CGRect(x: minX, y: minY, width: maxX - minX + 2, height: maxY - minY + 2)
}

func bitmap(_ pixels: Int, draw: (CGContext) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    draw(context.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// MARK: App icon: scale the rounded square to 824/1024 of the canvas (Apple's grid).

let shape = bounds { $0.alphaComponent > 0.5 }
func appIcon(pixels: Int) -> Data {
    bitmap(pixels) { cg in
        let canvas = CGFloat(pixels)
        let scale = canvas * (824.0 / 1024.0) / max(shape.width, shape.height)
        let drawW = CGFloat(width) * scale, drawH = CGFloat(height) * scale
        // Center the shape (not the whole image) in the canvas. CG origin is bottom-left.
        let shapeMidX = shape.midX * scale, shapeMidY = (CGFloat(height) - shape.midY) * scale
        let origin = CGPoint(x: canvas / 2 - shapeMidX, y: canvas / 2 - shapeMidY)
        // Subtle drop shadow like system icons.
        cg.setShadow(offset: CGSize(width: 0, height: -canvas * 0.01), blur: canvas * 0.02,
                     color: NSColor.black.withAlphaComponent(0.3).cgColor)
        cg.draw(sourceImage, in: CGRect(origin: origin, size: CGSize(width: drawW, height: drawH)))
    }
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("XClose-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try appIcon(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try appIcon(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", bundleDir.appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }

// MARK: Menu-bar icon: the star cut out of a rounded square, as a template image.
// The star is extracted as an alpha mask so anti-aliased edges stay smooth.

func isStar(_ c: NSColor) -> Bool { c.alphaComponent > 0.5 && c.greenComponent > 0.5 }
let star = bounds(isStar).insetBy(dx: -4, dy: -4)
let side = max(star.width, star.height)
let starSquare = CGRect(x: star.midX - side / 2, y: star.midY - side / 2, width: side, height: side)

let mask = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                            bytesPerRow: 0, bitsPerPixel: 0)!
for y in 0..<height {
    for x in 0..<width {
        let c = source.colorAt(x: x, y: y)!
        let alpha = c.alphaComponent > 0.5 ? min(1, max(0, (c.greenComponent - 0.1) / 0.8)) : 0
        mask.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: alpha), atX: x, y: y)
    }
}
let maskImage = mask.cgImage!.cropping(to: starSquare)!

// 18 pt template image: a solid rounded square with the star cut out of it. macOS
// tints template images to the menu bar (white on dark, black on light), so the
// tile always contrasts with the bar and the star shows through it.
for (scale, suffix) in [(1, ""), (2, "@2x")] {
    let pixels = 18 * scale
    let data = bitmap(pixels) { cg in
        let unit = CGFloat(scale)
        let tile = CGRect(x: unit, y: unit, width: CGFloat(pixels) - unit * 2, height: CGFloat(pixels) - unit * 2)
        cg.addPath(CGPath(roundedRect: tile, cornerWidth: tile.width * 0.26, cornerHeight: tile.width * 0.26, transform: nil))
        cg.setFillColor(CGColor(gray: 0, alpha: 1))
        cg.fillPath()
        cg.setBlendMode(.destinationOut)
        cg.draw(maskImage, in: tile.insetBy(dx: tile.width * 0.1, dy: tile.width * 0.1))
    }
    try data.write(to: bundleDir.appendingPathComponent("MenuBarIcon\(suffix).png"))
}
print("Wrote AppIcon.icns and MenuBarIcon[@2x].png to \(bundleDir.path)")
