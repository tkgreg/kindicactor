// Generates the app icon: a keycap with an indicator light, stacked on two layer plates.
// Usage: swift Tools/make-icon.swift Resources/AppIcon.icns [preview.png]
import AppKit

let canvas: CGFloat = 1024

/// Superellipse close to the macOS app icon shape.
func squircle(_ rect: CGRect, exponent: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let steps = 360
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = a * copysign(pow(abs(c), 2 / exponent), c)
        let y = b * copysign(pow(abs(s), 2 / exponent), s)
        let point = CGPoint(x: rect.midX + x, y: rect.midY + y)
        i == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func fill(_ ctx: CGContext, _ path: CGPath, top: CGColor, bottom: CGColor, in rect: CGRect) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    ctx.restoreGState()
}

func drawIcon(_ ctx: CGContext) {
    // Background tile with the standard drop shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = squircle(tile)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(tilePath)
    ctx.setFillColor(color(0x1C1F26))
    ctx.fillPath()
    ctx.restoreGState()
    fill(ctx, tilePath, top: color(0x3B4150), bottom: color(0x16181E), in: tile)

    // Layer plates under the keycap.
    let keySize: CGFloat = 460
    let keyCenter = CGPoint(x: 512, y: 560)
    let plates: [(dy: CGFloat, top: UInt32, bottom: UInt32)] = [
        (-150, 0x4F5BD5, 0x3A44A8),
        (-82, 0x22B8A7, 0x16897C),
    ]
    for plate in plates {
        let rect = CGRect(x: keyCenter.x - keySize / 2, y: keyCenter.y - keySize / 2 + plate.dy,
                          width: keySize, height: keySize)
        let path = squircle(rect, exponent: 4)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.45))
        ctx.addPath(path)
        ctx.setFillColor(color(plate.bottom))
        ctx.fillPath()
        ctx.restoreGState()
        fill(ctx, path, top: color(plate.top), bottom: color(plate.bottom), in: rect)
    }

    // Keycap: skirt plus a raised top face.
    let skirt = CGRect(x: keyCenter.x - keySize / 2, y: keyCenter.y - keySize / 2, width: keySize, height: keySize)
    let skirtPath = squircle(skirt, exponent: 4)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x000000, 0.5))
    ctx.addPath(skirtPath)
    ctx.setFillColor(color(0xB4B9C4))
    ctx.fillPath()
    ctx.restoreGState()
    fill(ctx, skirtPath, top: color(0xD5D9E1), bottom: color(0xA3A8B4), in: skirt)

    let face = CGRect(x: skirt.minX + 52, y: skirt.minY + 78, width: keySize - 104, height: keySize - 112)
    let facePath = squircle(face, exponent: 4)
    fill(ctx, facePath, top: color(0xFBFBFD), bottom: color(0xE2E5EB), in: face)

    // Legend.
    let base = NSFont.systemFont(ofSize: 240, weight: .heavy)
    let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 240) } ?? base
    let legend = NSAttributedString(string: "K", attributes: [.font: font, .foregroundColor: NSColor(cgColor: color(0x2A2E37))!])
    let legendSize = legend.size()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    legend.draw(at: CGPoint(x: face.midX - legendSize.width / 2 - 14,
                            y: face.midY - font.capHeight / 2 + font.descender))
    NSGraphicsContext.restoreGraphicsState()

    // Indicator light with a glow.
    let led = CGRect(x: face.maxX - 92, y: face.maxY - 92, width: 50, height: 50)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40, color: color(0x3DF08A, 0.95))
    ctx.setFillColor(color(0x3DF08A))
    ctx.fillEllipse(in: led)
    ctx.restoreGState()
    ctx.setFillColor(color(0xFFFFFF, 0.65))
    ctx.fillEllipse(in: led.insetBy(dx: 15, dy: 15).offsetBy(dx: -5, dy: 5))
}

func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    drawIcon(ctx)
    return rep
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: make-icon.swift <output.icns> [preview.png]")
    exit(1)
}
let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-\(getpid()).iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let png = render(pixels: points * scale).representation(using: .png, properties: [:])!
        try! png.write(to: iconset.appendingPathComponent(name))
    }
}
if args.count >= 3 {
    try! render(pixels: 1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", args[1]]
try! iconutil.run()
iconutil.waitUntilExit()
try? fm.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "Wrote \(args[1])" : "iconutil failed")
