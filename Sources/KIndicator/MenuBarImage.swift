import AppKit

/// Template images for the status item.
enum MenuBarImage {
    private static var font: NSFont { NSFont.menuBarFont(ofSize: 0) }
    /// Other menu bar extras draw their glyphs about 15% larger than the 13 pt menu bar font.
    private static let iconPointSize: CGFloat = 15

    /// Outline box for letter icons. Same height, line and corners as SF Symbols' "square"
    /// at 17 pt, which is as tall as the other menu bar icons.
    private enum Box {
        static let height: CGFloat = 15.5
        static let lineWidth: CGFloat = 1.25
        static let cornerRadius: CGFloat = 2.75
        static let margin: CGFloat = 0.5
    }

    /// A layer icon: `spec` is an SF Symbol name (e.g. "sun.max"), otherwise up to three
    /// characters in an outline box. One letter gets a square like SF Symbols' "w.square";
    /// longer labels widen the box so the sides are as roomy as the top and bottom.
    static func icon(_ spec: String) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: iconPointSize, weight: .regular)
        if let symbol = NSImage(systemSymbolName: spec, accessibilityDescription: spec)?
            .withSymbolConfiguration(configuration) {
            return symbol
        }

        let text = String(spec.prefix(3))
        let letterFont = NSFont.systemFont(ofSize: text.count == 1 ? 11.25 : 9.5, weight: .medium)
        let letters = NSAttributedString(string: text, attributes: [.font: letterFont, .foregroundColor: NSColor.black])
        let ink = CTLineGetImageBounds(CTLineCreateWithAttributedString(letters), nil)

        let gap = (Box.height - 2 * Box.lineWidth - letterFont.capHeight) / 2
        let width = text.count == 1
            ? Box.height
            : max(Box.height, ceil((ink.width + 2 * (gap + Box.lineWidth)) * 2) / 2)
        let box = NSRect(x: Box.margin, y: Box.margin, width: width, height: Box.height)

        let image = NSImage(size: NSSize(width: width + 2 * Box.margin, height: Box.height + 2 * Box.margin),
                            flipped: false) { _ in
            let inset = Box.lineWidth / 2
            let outline = NSBezierPath(roundedRect: box.insetBy(dx: inset, dy: inset),
                                       xRadius: Box.cornerRadius - inset, yRadius: Box.cornerRadius - inset)
            outline.lineWidth = Box.lineWidth
            NSColor.black.setStroke()
            outline.stroke()
            // Centre the ink, not the advance width, so side bearings don't skew it.
            letters.draw(at: NSPoint(
                x: snap(box.midX - ink.midX),
                y: snap(box.midY - letterFont.capHeight / 2) + letterFont.descender
            ))
            return true
        }
        image.alignmentRect = box
        image.isTemplate = true
        image.accessibilityDescription = text
        return image
    }

    /// The icon followed by `text`, drawn as one image so both sit on the middle of the
    /// capitals. Given separately, the status item centers the icon lower than the text.
    static func icon(_ icon: NSImage, followedBy text: String) -> NSImage {
        let font = font
        let title = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black])
        let spacing: CGFloat = 5
        let height = NSStatusBar.system.thickness
        let size = NSSize(width: ceil(icon.size.width + spacing + title.size().width), height: height)
        let midline = height / 2

        let image = NSImage(size: size, flipped: false) { _ in
            icon.draw(in: NSRect(
                x: 0,
                y: snap(midline - icon.alignmentRect.midY),
                width: icon.size.width,
                height: icon.size.height
            ))
            let baseline = snap(midline - font.capHeight / 2)
            title.draw(at: NSPoint(x: icon.size.width + spacing, y: baseline + font.descender))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = text
        return image
    }

    /// Rounds to the nearest Retina pixel so edges stay crisp.
    private static func snap(_ value: CGFloat) -> CGFloat {
        (value * 2).rounded() / 2
    }
}
