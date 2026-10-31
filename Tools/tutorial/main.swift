import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Renders the website's tutorial GIF: a looping demo of Trick or Treat and Undecorate on a mock Desktop,
// drawn with the app's real costume renderer and reveal card.
//
//   swiftc -swift-version 5 -O Sources/App/{Costumes,Gacha,Popup}.swift Tools/tutorial/main.swift -o tutorial
//   ./tutorial docs/tutorial.gif

let W = 720, H = 450
let width = CGFloat(W), height = CGFloat(H)

/// Top-left based rect → Core Graphics (bottom-left) rect.
func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: height - y - h, width: w, height: h)
}

func makeContext() -> CGContext {
    let c = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    return c
}

func text(_ string: String, in rect: CGRect, size: CGFloat, weight: NSFont.Weight = .regular,
          color: NSColor = .white, align: NSTextAlignment = .left, shadow: Bool = false) {
    let style = NSMutableParagraphStyle()
    style.alignment = align
    var attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                .foregroundColor: color, .paragraphStyle: style]
    if shadow {
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(0.8)
        s.shadowBlurRadius = 3
        s.shadowOffset = NSSize(width: 0, height: -1)
        attrs[.shadow] = s
    }
    NSAttributedString(string: string, attributes: attrs).draw(in: rect)
}

// MARK: Assets

let folderIcon = NSWorkspace.shared.icon(for: .folder)
let plainFolder = CostumeRenderer.snapshot(folderIcon)
let witchFolder = CostumeRenderer.render(.witchHat, shiny: false, base: folderIcon)
let textFile = CostumeRenderer.snapshot(NSWorkspace.shared.icon(for: .plainText))

func renderSwiftUI<V: View>(_ view: V) -> CGImage {
    MainActor.assumeIsolated {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.cgImage!
    }
}

let revealCard = renderSwiftUI(RevealView(
    items: [RevealItem(name: "Homework", pull: Pull(costume: .witchHat, shiny: false), isNew: true, icon: CostumeRenderer.nsImage(witchFolder))],
    collectedCount: 1, animate: false))
let undoCard = renderSwiftUI(NoticeView(emoji: "🧹", text: "Costume off! “Homework” is back to normal."))

/// Flat colours on purpose: GIFs compress solid areas far better than gradients.
let wallpaper: CGImage = {
    let c = makeContext()
    c.setFillColor(hex(0x24163D))
    c.fill(R(0, 0, width, height))
    c.setFillColor(hex(0x2E1D4D))
    c.fillEllipse(in: R(56, 56, 108, 108))
    c.setFillColor(hex(0xFFF1C2))
    c.fillEllipse(in: R(72, 72, 76, 76))
    c.setFillColor(hex(0xCFC3E8))
    for (x, y) in [(260, 60), (330, 140), (420, 70), (520, 120), (200, 220), (300, 330), (60, 300), (470, 260)] {
        c.fill(R(CGFloat(x), CGFloat(y), 2, 2))
    }
    return c.makeImage()!
}()

// MARK: Scene

struct DesktopItem {
    let name: String
    let center: CGPoint // top-left based
}

let items = [
    DesktopItem(name: "Homework", center: CGPoint(x: width - 78, y: 78)),
    DesktopItem(name: "Taxes 2026", center: CGPoint(x: width - 78, y: 190)),
    DesktopItem(name: "Party Notes.txt", center: CGPoint(x: width - 78, y: 302)),
]

let menuItems = ["Open", "Get Info", "Rename", "Duplicate", "-",
                 "🎃 Trick or Treat", "🧹 Undecorate", "🧹 Undecorate Desktop", "-", "Copy “Homework”"]
let menuWidth: CGFloat = 220, rowHeight: CGFloat = 23, separatorHeight: CGFloat = 9, menuPad: CGFloat = 6

func rowTop(_ index: Int) -> CGFloat {
    menuItems[..<index].reduce(menuPad) { $0 + ($1 == "-" ? separatorHeight : rowHeight) }
}

var menuHeight: CGFloat { rowTop(menuItems.count) + menuPad }

struct Scene {
    var cursor = CGPoint(x: 280, y: 300)
    var selected = false
    var menuOrigin: CGPoint?
    var dressed = false
    var iconScale: CGFloat = 1
    var card: CGImage?
    var cardScale: CGFloat = 1
    var cardAlpha: CGFloat = 1
    var caption = ""
}

func hoveredRow(_ s: Scene) -> Int? {
    guard let o = s.menuOrigin, s.cursor.x > o.x, s.cursor.x < o.x + menuWidth else { return nil }
    for i in menuItems.indices where menuItems[i] != "-" {
        let top = o.y + rowTop(i)
        if s.cursor.y >= top && s.cursor.y < top + rowHeight { return i }
    }
    return nil
}

func render(_ s: Scene) -> CGImage {
    let c = makeContext()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
    c.draw(wallpaper, in: R(0, 0, width, height))

    // Menu bar
    c.setFillColor(hex(0x000000, 0.32))
    c.fill(R(0, 0, width, 24))
    text("\u{F8FF}    Finder", in: R(14, 4, 120, 18), size: 13, weight: .bold)
    text("File    Edit    View    Go    Window    Help", in: R(104, 4, 320, 18), size: 13)
    text("Fri 31 Oct   9:41 PM", in: R(width - 170, 4, 156, 18), size: 13, align: .right)

    // Desktop icons
    for (i, item) in items.enumerated() {
        let isTarget = i == 0
        let size: CGFloat = 70 * (isTarget ? s.iconScale : 1)
        if isTarget && s.selected {
            c.setFillColor(hex(0xFFFFFF, 0.18))
            c.addPath(CGPath(roundedRect: R(item.center.x - 42, item.center.y - 40, 84, 80), cornerWidth: 8, cornerHeight: 8, transform: nil))
            c.fillPath()
        }
        let image = i == 2 ? textFile : (isTarget && s.dressed ? witchFolder : plainFolder)
        c.draw(image, in: R(item.center.x - size / 2, item.center.y - size / 2, size, size))
        let label = R(item.center.x - 56, item.center.y + 40, 112, 18)
        if isTarget && s.selected {
            let pill = NSAttributedString(string: item.name, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).size().width + 12
            c.setFillColor(hex(0x0A64D6))
            c.addPath(CGPath(roundedRect: R(item.center.x - pill / 2, item.center.y + 40, pill, 17), cornerWidth: 4, cornerHeight: 4, transform: nil))
            c.fillPath()
        }
        text(item.name, in: label, size: 12, weight: .medium, align: .center, shadow: !(isTarget && s.selected))
    }

    // Reveal or notice card, to the left of the icons
    if let card = s.card {
        let w = CGFloat(card.width) / 2 * 0.72 * s.cardScale, h = CGFloat(card.height) / 2 * 0.72 * s.cardScale
        let anchor = CGPoint(x: width - 150 - 108, y: card === undoCard ? 92 : 168)
        c.saveGState()
        c.setAlpha(s.cardAlpha)
        c.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: hex(0x000000, 0.5))
        c.draw(card, in: R(anchor.x - w / 2, anchor.y - h / 2, w, h))
        c.restoreGState()
    }

    // Context menu
    if let o = s.menuOrigin {
        let frame = R(o.x, o.y, menuWidth, menuHeight)
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: hex(0x000000, 0.45))
        c.setFillColor(hex(0xF2F0F5, 0.97))
        c.addPath(CGPath(roundedRect: frame, cornerWidth: 11, cornerHeight: 11, transform: nil))
        c.fillPath()
        c.restoreGState()
        let hovered = hoveredRow(s)
        for (i, title) in menuItems.enumerated() {
            let top = o.y + rowTop(i)
            if title == "-" {
                c.setFillColor(hex(0x000000, 0.12))
                c.fill(R(o.x + 12, top + 4, menuWidth - 24, 1))
                continue
            }
            if i == hovered {
                c.setFillColor(hex(0x0A64D6))
                c.addPath(CGPath(roundedRect: R(o.x + 5, top, menuWidth - 10, rowHeight), cornerWidth: 6, cornerHeight: 6, transform: nil))
                c.fillPath()
            }
            text(title, in: R(o.x + 16, top + 3, menuWidth - 24, rowHeight), size: 13,
                 weight: title.hasPrefix("🎃") || title.hasPrefix("🧹") ? .semibold : .regular,
                 color: i == hovered ? .white : NSColor(white: 0.1, alpha: 1))
        }
    }

    // Step caption
    if !s.caption.isEmpty {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16, weight: .semibold)]
        let w = NSAttributedString(string: s.caption, attributes: attrs).size().width + 32
        c.setFillColor(hex(0x000000, 0.6))
        c.addPath(CGPath(roundedRect: R(20, height - 58, w, 38), cornerWidth: 19, cornerHeight: 19, transform: nil))
        c.fillPath()
        text(s.caption, in: R(36, height - 49, w, 24), size: 16, weight: .semibold)
    }

    // Pointer
    let p = s.cursor
    let arrow = CGMutablePath()
    let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 19), (4.5, 14.5), (7.5, 21.5), (10.5, 20.2), (7.6, 13.5), (13.5, 13.5)]
    arrow.addLines(between: pts.map { CGPoint(x: p.x + $0.0, y: height - p.y - $0.1) })
    arrow.closeSubpath()
    c.addPath(arrow)
    c.setFillColor(hex(0x000000))
    c.setStrokeColor(hex(0xFFFFFF))
    c.setLineWidth(1.6)
    c.drawPath(using: .fillStroke)

    return c.makeImage()!
}

// MARK: Timeline

/// Stretches every delay; raise it to slow the whole demo down.
let pace = 1.4

var scene = Scene()
var frames: [(CGImage, Double)] = []

func shot(_ delay: Double) { frames.append((render(scene), delay * pace)) }

func move(to target: CGPoint, steps: Int) {
    let start = scene.cursor
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        let e = CGFloat(t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2)
        scene.cursor = CGPoint(x: start.x + (target.x - start.x) * e, y: start.y + (target.y - start.y) * e)
        shot(0.045)
    }
}

func rowCenter(_ index: Int) -> CGPoint {
    let o = scene.menuOrigin!
    return CGPoint(x: o.x + 110, y: o.y + rowTop(index) + rowHeight / 2)
}

func rightClickHomework() {
    move(to: CGPoint(x: items[0].center.x - 4, y: items[0].center.y + 4), steps: 7)
    scene.selected = true
    shot(0.25)
    scene.menuOrigin = CGPoint(x: scene.cursor.x - menuWidth - 4, y: scene.cursor.y)
    shot(0.45)
}

let start = scene.cursor

scene.caption = "1  Right-click any file or folder on your Desktop"
shot(0.9)
rightClickHomework()

scene.caption = "2  Choose 🎃 Trick or Treat"
move(to: rowCenter(5), steps: 6)
shot(0.6)

// Click: the folder pops into its costume and the reveal card springs in.
scene.menuOrigin = nil
scene.dressed = true
scene.card = revealCard
for (icon, card, alpha) in [(0.7, 0.55, 0.35), (1.14, 0.9, 0.8), (0.95, 1.05, 1.0), (1.0, 1.0, 1.0)] as [(CGFloat, CGFloat, CGFloat)] {
    scene.iconScale = icon; scene.cardScale = card; scene.cardAlpha = alpha
    shot(0.05)
}
scene.caption = "It gets a surprise costume!"
shot(2.6)
scene.cardAlpha = 0.45; shot(0.06)
scene.card = nil; scene.cardAlpha = 1; shot(0.5)

scene.caption = "3  Undecorate whenever you like"
rightClickHomework()
move(to: rowCenter(6), steps: 5)
shot(0.6)

scene.menuOrigin = nil
scene.dressed = false
scene.card = undoCard
for (icon, card, alpha) in [(0.8, 0.7, 0.4), (1.08, 1.03, 0.9), (1.0, 1.0, 1.0)] as [(CGFloat, CGFloat, CGFloat)] {
    scene.iconScale = icon; scene.cardScale = card; scene.cardAlpha = alpha
    shot(0.05)
}
shot(2.0)
scene.cardAlpha = 0.45; shot(0.06)
scene.card = nil; scene.cardAlpha = 1
scene.selected = false
scene.caption = ""
move(to: start, steps: 7)
shot(0.5)

// MARK: Write GIF

let url = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "tutorial.gif")
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for (image, delay) in frames {
    CGImageDestinationAddImage(dest, image, [kCGImagePropertyGIFDictionary: [
        kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay,
    ]] as CFDictionary)
}
guard CGImageDestinationFinalize(dest) else { fatalError("could not write GIF") }
let total = frames.reduce(0) { $0 + $1.1 }
print("wrote \(url.path): \(frames.count) frames, \(String(format: "%.1f", total))s")
