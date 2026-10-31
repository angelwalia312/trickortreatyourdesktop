import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

// Renders the YouTube launch video: a ~40 s 1080p animation on a mock Desktop, drawn with the app's real costume
// renderer and reveal cards, with the app's sound effects over a synthesised music-box track.
//
//   swiftc -swift-version 5 -O Sources/App/{Costumes,Gacha,Popup,AppIcon}.swift Tools/video/main.swift -o /tmp/video
//   /tmp/video --audio audio.wav --frames | ffmpeg -f rawvideo -pix_fmt rgba -s 1920x1080 -r 30 -i - ... video.mp4
//   /tmp/video --stills sheet.png 2.0 8.5 ...      (preview chosen moments as a contact sheet)
//   add --vertical for the 1080×1920 YouTube Shorts / TikTok cut

let args = CommandLine.arguments
let vertical = args.contains("--vertical")

let fps = 30.0
let pixelWidth = vertical ? 1080 : 1920, pixelHeight = vertical ? 1920 : 1080
// Everything is laid out in points (960×540, or 540×960 vertical) and drawn at 2×, like a Retina screen.
let width: CGFloat = vertical ? 540 : 960, height: CGFloat = vertical ? 960 : 540
let soundsDir = URL(fileURLWithPath: "Resources/Sounds")

/// Top-left based rect → Core Graphics (bottom-left) rect, in points.
func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: height - y - h, width: w, height: h)
}

func makeContext(_ w: Int = pixelWidth, _ h: Int = pixelHeight, scale: CGFloat = 2) -> CGContext {
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    c.scaleBy(x: scale, y: scale)
    return c
}

func text(_ string: String, in rect: CGRect, size: CGFloat, weight: NSFont.Weight = .regular,
          color: NSColor = .white, align: NSTextAlignment = .left, shadow: Bool = false, alpha: CGFloat = 1) {
    let style = NSMutableParagraphStyle()
    style.alignment = align
    var attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                .foregroundColor: color.withAlphaComponent(color.alphaComponent * alpha),
                                                .paragraphStyle: style]
    if shadow {
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(0.8 * alpha)
        s.shadowBlurRadius = 3
        s.shadowOffset = NSSize(width: 0, height: -1)
        attrs[.shadow] = s
    }
    NSAttributedString(string: string, attributes: attrs).draw(in: rect)
}

func textWidth(_ string: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
    NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).size().width
}

func roundedRect(_ c: CGContext, _ rect: CGRect, _ radius: CGFloat, fill: CGColor, stroke: CGColor? = nil, line: CGFloat = 1) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    c.addPath(path)
    c.setFillColor(fill)
    c.fillPath()
    if let stroke {
        c.addPath(path)
        c.setStrokeColor(stroke)
        c.setLineWidth(line)
        c.strokePath()
    }
}

/// Downscales a 1024 render once so per-frame drawing stays fast.
func shrink(_ image: CGImage, _ px: Int = 256) -> CGImage {
    let c = makeContext(px, px, scale: 1)
    c.draw(image, in: CGRect(x: 0, y: 0, width: px, height: px))
    return c.makeImage()!
}

let orange = NSColor(red: 1, green: 0.56, blue: 0.16, alpha: 1)
let lavender = NSColor(red: 0.78, green: 0.71, blue: 0.9, alpha: 1)

// MARK: - Assets

let folderIcon = NSWorkspace.shared.icon(for: .folder)

/// Finder-style preview card for the fake screenshot file.
let screenshotLook: NSImage = {
    let source = args.firstIndex(of: "--screenshot").flatMap { NSImage(contentsOfFile: args[$0 + 1]) }
    let preview = NSImage(size: NSSize(width: 1440, height: 900), flipped: false) { r in
        if let source { source.draw(in: r, from: NSRect(x: 0, y: 270, width: 1440, height: 900), operation: .copy, fraction: 1) }
        else {
            NSGradient(colors: [.systemPink, .systemPurple])!.draw(in: r, angle: 60)
        }
        return true
    }
    let pad: CGFloat = 1440 * 0.03
    return NSImage(size: NSSize(width: 1440 + pad * 2, height: 900 + pad * 2), flipped: false) { rect in
        let card = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: pad, yRadius: pad)
        NSColor.white.setFill(); card.fill()
        preview.draw(in: rect.insetBy(dx: pad, dy: pad))
        NSColor(white: 0, alpha: 0.2).setStroke(); card.lineWidth = 3; card.stroke()
        return true
    }
}()

struct DesktopItem {
    let name: String
    let center: CGPoint
    let plain: CGImage
    let costume: Costume
    let shiny: Bool
    let dressed: CGImage
}

func item(_ name: String, _ x: CGFloat, _ y: CGFloat, look: NSImage, _ costume: Costume, shiny: Bool = false) -> DesktopItem {
    DesktopItem(name: name, center: CGPoint(x: x, y: y), plain: shrink(CostumeRenderer.snapshot(look)), costume: costume,
                shiny: shiny, dressed: shrink(CostumeRenderer.render(costume, shiny: shiny, base: look)))
}

/// Landscape: two columns at the top right, like a real Desktop. Vertical: a 3×3 grid kept clear of the
/// buttons and captions YouTube draws over the right side and bottom of a Short.
let spots: [CGPoint] = vertical
    ? [(400, 250), (400, 365), (400, 480), (180, 250), (290, 250), (290, 365), (290, 480)].map { CGPoint(x: $0.0, y: $0.1) }
    : [(890, 92), (890, 200), (890, 308), (890, 416), (790, 92), (790, 200), (790, 308)].map { CGPoint(x: $0.0, y: $0.1) }

let items: [DesktopItem] = [
    item("Homework", spots[0].x, spots[0].y, look: folderIcon, .witchHat),
    item("Taxes 2026", spots[1].x, spots[1].y, look: folderIcon, .vampire),
    item("Screenshot.png", spots[2].x, spots[2].y, look: screenshotLook, .ghost),
    item("Party Notes.txt", spots[3].x, spots[3].y, look: NSWorkspace.shared.icon(for: .plainText), .pumpkin),
    item("Projects", spots[4].x, spots[4].y, look: folderIcon, .mummy),
    item("Invitation.pdf", spots[5].x, spots[5].y, look: NSWorkspace.shared.icon(for: .pdf), .frankenstein),
    item("Photos", spots[6].x, spots[6].y, look: folderIcon, .vampire, shiny: true),
]
let iconSize: CGFloat = vertical ? 76 : 64
let HOMEWORK = 0, PHOTOS = 6

func renderSwiftUI<V: View>(_ view: V) -> CGImage {
    MainActor.assumeIsolated {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.cgImage!
    }
}

func reveal(_ index: Int, collected: Int) -> CGImage {
    let it = items[index]
    let icon = CostumeRenderer.nsImage(CostumeRenderer.render(it.costume, shiny: it.shiny, base: it.costume == .ghost ? screenshotLook : folderIcon))
    return renderSwiftUI(RevealView(items: [RevealItem(name: it.name, pull: Pull(costume: it.costume, shiny: it.shiny), isNew: true, icon: icon)],
                                    collectedCount: collected, animate: false))
}

let cards: [String: CGImage] = [
    "homework": reveal(HOMEWORK, collected: 1),
    "photos": reveal(PHOTOS, collected: 7),
    "undo": renderSwiftUI(NoticeView(emoji: "🧹", text: "Undecorated 7 items on your Desktop.")),
]

let appIcon = shrink(AppIcon.image(), 512)

let wallpaper: CGImage = {
    let c = makeContext()
    let sky = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                         colors: [hex(0x3A2363), hex(0x1C1033), hex(0x0C0716)] as CFArray, locations: [0, 0.55, 1])!
    c.drawLinearGradient(sky, start: CGPoint(x: 0, y: height), end: CGPoint(x: width * 0.35, y: 0),
                         options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    let moon = vertical ? CGPoint(x: 92, y: height - 790) : CGPoint(x: 150, y: height - 150)
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [hex(0xFFE9A0, 0.4), hex(0xFFE9A0, 0)] as CFArray, locations: nil)!
    c.drawRadialGradient(glow, startCenter: moon, startRadius: 0, endCenter: moon, endRadius: 210, options: [])
    c.setFillColor(hex(0xFFF3C8))
    c.fillEllipse(in: CGRect(x: moon.x - 52, y: moon.y - 52, width: 104, height: 104))
    c.setFillColor(hex(0xFFFFFF, 0.75))
    let stars: [(CGFloat, CGFloat, CGFloat)] = vertical
        ? [(60, 140, 1.6), (160, 90, 1.2), (250, 300, 1.4), (470, 620, 1.2), (420, 720, 1.6), (200, 820, 1.2),
           (60, 880, 1.4), (330, 900, 1.2), (500, 840, 1.6), (140, 520, 1.2)]
        : [(330, 70, 1.6), (430, 160, 1.2), (560, 80, 1.8), (650, 150, 1.2), (260, 280, 1.4), (420, 390, 1.2),
           (90, 360, 1.6), (600, 300, 1.2), (180, 470, 1.4), (520, 480, 1.2)]
    for (x, y, r) in stars {
        c.fillEllipse(in: R(x, y, r * 2, r * 2))
    }
    return c.makeImage()!
}()

// MARK: - Scene state

enum Mode { case title, desktop, collection, outro }

struct Flash {
    var index: Int
    var label: String
    var age: Double // 0…1
}

struct Shot {
    var mode = Mode.title
    var dim: CGFloat = 0 // black overlay for transitions
    var intro: Double = 0 // title / outro / collection animation clock, seconds
    var cursor = CGPoint(x: 420, y: 400)
    var showCursor = true
    var selected: Int?
    var menuAt: CGPoint?
    var dressed = Set<Int>()
    var pop: [Int: CGFloat] = [:]
    var card: String?
    var cardScale: CGFloat = 1
    var cardAlpha: CGFloat = 1
    var caption = ""
    var captionAlpha: CGFloat = 1
    var flashes: [Flash] = []
    var tiles = 0
}

let menuItems = ["Open", "Get Info", "Rename", "Duplicate", "-",
                 "🎃 Trick or Treat", "🧹 Undecorate", "🧹 Undecorate Desktop", "-", "Copy"]
let menuWidth: CGFloat = 220, rowHeight: CGFloat = 23, separatorHeight: CGFloat = 9, menuPad: CGFloat = 6

func rowTop(_ index: Int) -> CGFloat {
    menuItems[..<index].reduce(menuPad) { $0 + ($1 == "-" ? separatorHeight : rowHeight) }
}

let menuHeight = rowTop(menuItems.count) + menuPad

func hoveredRow(_ s: Shot) -> Int? {
    guard let o = s.menuAt, s.cursor.x > o.x, s.cursor.x < o.x + menuWidth else { return nil }
    return menuItems.indices.first { i in
        menuItems[i] != "-" && s.cursor.y >= o.y + rowTop(i) && s.cursor.y < o.y + rowTop(i) + rowHeight
    }
}

// MARK: - Drawing

func drawDesktop(_ c: CGContext, _ s: Shot) {
    c.draw(wallpaper, in: R(0, 0, width, height))

    c.setFillColor(hex(0x000000, 0.3))
    c.fill(R(0, 0, width, 26))
    text("\u{F8FF}     Finder", in: R(16, 5, 140, 18), size: 13, weight: .bold)
    if !vertical { text("File     Edit     View     Go     Window     Help", in: R(120, 5, 360, 18), size: 13) }
    text("Fri 31 Oct   9:41 PM", in: R(width - 186, 5, 170, 18), size: 13, align: .right)

    for (i, it) in items.enumerated() {
        let size = iconSize * (s.pop[i] ?? 1)
        let half = iconSize / 2 + 6, labelSize: CGFloat = vertical ? 12.5 : 11
        if s.selected == i {
            roundedRect(c, R(it.center.x - half - 2, it.center.y - half, half * 2 + 4, half * 2), 8, fill: hex(0xFFFFFF, 0.18))
        }
        c.draw(s.dressed.contains(i) ? it.dressed : it.plain, in: R(it.center.x - size / 2, it.center.y - size / 2, size, size))
        let labelTop = it.center.y + half
        if s.selected == i {
            let w = textWidth(it.name, size: labelSize, weight: .medium) + 10
            roundedRect(c, R(it.center.x - w / 2, labelTop, w, labelSize + 4), 4, fill: hex(0x0A64D6))
        }
        text(it.name, in: R(it.center.x - 55, labelTop, 110, labelSize + 5), size: labelSize, weight: .medium, align: .center,
             shadow: s.selected != i)
    }

    for f in s.flashes {
        let it = items[f.index]
        let alpha = CGFloat(f.age < 0.15 ? f.age / 0.15 : f.age > 0.7 ? (1 - f.age) / 0.3 : 1)
        let rise = CGFloat(f.age) * 14
        let fontSize: CGFloat = vertical ? 30 : 17
        let w = textWidth(f.label, size: fontSize, weight: .heavy) + fontSize * 1.6
        let x: CGFloat = vertical ? width / 2 - w / 2 : 728 - w
        let y: CGFloat = vertical ? 625 : it.center.y
        c.saveGState()
        c.setAlpha(alpha)
        roundedRect(c, R(x, y - fontSize * 0.9 - rise, w, fontSize * 1.8), fontSize * 0.9, fill: orange.cgColor)
        text(f.label, in: R(x, y - fontSize * 0.65 - rise, w, fontSize * 1.4), size: fontSize, weight: .heavy,
             color: NSColor(red: 0.12, green: 0.05, blue: 0, alpha: 1), align: .center)
        c.restoreGState()
    }

    if let key = s.card, let card = cards[key] {
        let size: CGFloat = key == "undo" ? 1.2 : vertical ? 0.86 : 0.85
        let w = CGFloat(card.width) / 2 * size * s.cardScale, h = CGFloat(card.height) / 2 * size * s.cardScale
        // On a Short the reveal pops up over the icons, keeping it clear of YouTube's captions at the bottom.
        let anchor = vertical ? CGPoint(x: width / 2, y: key == "undo" ? 625 : 400)
                              : key == "undo" ? CGPoint(x: 560, y: 120) : CGPoint(x: 560, y: 230)
        c.saveGState()
        c.setAlpha(s.cardAlpha)
        c.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: hex(0x000000, 0.55))
        c.draw(card, in: R(anchor.x - w / 2, anchor.y - h / 2, w, h))
        c.restoreGState()
    }

    if let o = s.menuAt {
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: hex(0x000000, 0.45))
        roundedRect(c, R(o.x, o.y, menuWidth, menuHeight), 11, fill: hex(0xF2F0F5, 0.97))
        c.restoreGState()
        let hovered = hoveredRow(s)
        for (i, title) in menuItems.enumerated() {
            let top = o.y + rowTop(i)
            if title == "-" {
                c.setFillColor(hex(0x000000, 0.12))
                c.fill(R(o.x + 12, top + 4, menuWidth - 24, 1))
                continue
            }
            if i == hovered { roundedRect(c, R(o.x + 5, top, menuWidth - 10, rowHeight), 6, fill: hex(0x0A64D6)) }
            text(title, in: R(o.x + 16, top + 3, menuWidth - 24, rowHeight), size: 13,
                 weight: title.hasPrefix("🎃") || title.hasPrefix("🧹") ? .semibold : .regular,
                 color: i == hovered ? .white : NSColor(white: 0.1, alpha: 1))
        }
    }

    if vertical && !s.caption.isEmpty {
        let font = NSFont.systemFont(ofSize: 27, weight: .heavy)
        let box = NSAttributedString(string: s.caption, attributes: [.font: font])
            .boundingRect(with: NSSize(width: 410, height: 400), options: [.usesLineFragmentOrigin])
        let w = ceil(box.width) + 50, h = ceil(box.height) + 28
        roundedRect(c, R(width / 2 - w / 2, 96, w, h), min(28, h / 2), fill: hex(0x000000, 0.66))
        text(s.caption, in: R(width / 2 - w / 2 + 25, 96 + 14, w - 50, h), size: 27, weight: .heavy, align: .center)
    } else if !s.caption.isEmpty && s.captionAlpha > 0 {
        let w = textWidth(s.caption, size: 22, weight: .bold) + 44
        c.saveGState()
        c.setAlpha(s.captionAlpha)
        roundedRect(c, R(28, height - 82, w, 50), 25, fill: hex(0x000000, 0.62))
        text(s.caption, in: R(50, height - 70, w, 30), size: 22, weight: .bold)
        c.restoreGState()
    }

    if s.showCursor {
        let p = s.cursor, k: CGFloat = 1.25
        let arrow = CGMutablePath()
        let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 19), (4.5, 14.5), (7.5, 21.5), (10.5, 20.2), (7.6, 13.5), (13.5, 13.5)]
        arrow.addLines(between: pts.map { CGPoint(x: p.x + $0.0 * k, y: height - p.y - $0.1 * k) })
        arrow.closeSubpath()
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -2), blur: 4, color: hex(0x000000, 0.4))
        c.addPath(arrow)
        c.setFillColor(hex(0x000000))
        c.setStrokeColor(hex(0xFFFFFF))
        c.setLineWidth(1.6)
        c.drawPath(using: .fillStroke)
        c.restoreGState()
    }
}

func easeOutBack(_ p: Double) -> Double {
    let c1 = 1.70158, c3 = c1 + 1
    return 1 + c3 * pow(p - 1, 3) + c1 * pow(p - 1, 2)
}

func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

func drawTitle(_ c: CGContext, _ s: Shot, outro: Bool) {
    c.draw(wallpaper, in: R(0, 0, width, height))
    c.setFillColor(hex(0x05020A, 0.45))
    c.fill(R(0, 0, width, height))
    let t = s.intro
    let iconP = clamp01(t / 0.7)
    let iconSize = (outro ? 120 : 170) * CGFloat(easeOutBack(iconP))
    let iconY: CGFloat = outro ? 92 : 108
    if iconSize > 1 {
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: hex(0x000000, 0.6))
        c.draw(appIcon, in: R(width / 2 - iconSize / 2, iconY + (outro ? 60 : 85) - iconSize / 2, iconSize, iconSize))
        c.restoreGState()
    }
    let titleP = CGFloat(clamp01((t - 0.45) / 0.45))
    let titleTop: CGFloat = outro ? 222 : 290
    text("Trick or Treat", in: R(0, titleTop + (1 - titleP) * 20, width, 90), size: outro ? 64 : 76, weight: .black,
         align: .center, alpha: titleP)
    let subP = CGFloat(clamp01((t - 0.9) / 0.45))
    if outro {
        text("Free for Mac  ·  macOS 13 or later", in: R(0, 308 + (1 - subP) * 14, width, 34), size: 24, weight: .semibold,
             color: lavender, align: .center, alpha: subP)
        let urlP = CGFloat(clamp01((t - 1.3) / 0.45))
        let url = "angelwalia312.github.io/trickortreatyourdesktop"
        let w = textWidth(url, size: 24, weight: .bold) + 48
        c.saveGState()
        c.setAlpha(urlP)
        roundedRect(c, R(width / 2 - w / 2, 362, w, 52), 26, fill: orange.cgColor)
        text(url, in: R(width / 2 - w / 2, 374, w, 32), size: 24, weight: .bold,
             color: NSColor(red: 0.12, green: 0.05, blue: 0, alpha: 1), align: .center)
        c.restoreGState()
        let byeP = CGFloat(clamp01((t - 1.9) / 0.45))
        text("Happy Halloween! 🎃", in: R(0, 440, width, 36), size: 24, weight: .semibold, align: .center, alpha: byeP)
    } else {
        text("Dress up your Mac's Desktop for Halloween", in: R(0, 384 + (1 - subP) * 14, width, 40), size: 30,
             weight: .bold, color: orange, align: .center, alpha: subP)
    }
}

func drawOutroVertical(_ c: CGContext, _ s: Shot) {
    c.draw(wallpaper, in: R(0, 0, width, height))
    c.setFillColor(hex(0x05020A, 0.55))
    c.fill(R(0, 0, width, height))
    let t = s.intro
    let iconSize = 150 * CGFloat(easeOutBack(clamp01(t / 0.7)))
    if iconSize > 1 {
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: hex(0x000000, 0.6))
        c.draw(appIcon, in: R(width / 2 - iconSize / 2, 250 - iconSize / 2, iconSize, iconSize))
        c.restoreGState()
    }
    let titleP = CGFloat(clamp01((t - 0.45) / 0.45))
    text("Trick or Treat", in: R(0, 346 + (1 - titleP) * 20, width, 80), size: 60, weight: .black, align: .center, alpha: titleP)
    let subP = CGFloat(clamp01((t - 0.9) / 0.45))
    text("Free for Mac  ·  macOS 13 or later", in: R(0, 430 + (1 - subP) * 14, width, 34), size: 23, weight: .semibold,
         color: lavender, align: .center, alpha: subP)
    let urlP = CGFloat(clamp01((t - 1.3) / 0.45))
    c.saveGState()
    c.setAlpha(urlP)
    roundedRect(c, R(44, 488, width - 88, 96), 28, fill: orange.cgColor)
    text("angelwalia312.github.io/\ntrickortreatyourdesktop", in: R(44, 502, width - 88, 80), size: 26, weight: .bold,
         color: NSColor(red: 0.12, green: 0.05, blue: 0, alpha: 1), align: .center)
    c.restoreGState()
    let byeP = CGFloat(clamp01((t - 1.9) / 0.45))
    text("Happy Halloween! 🎃", in: R(0, 618, width, 40), size: 28, weight: .semibold, align: .center, alpha: byeP)
}

func drawCollection(_ c: CGContext, _ s: Shot) {
    let backdrop = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [hex(0x241540), hex(0x0B0614)] as CFArray, locations: nil)!
    c.drawLinearGradient(backdrop, start: CGPoint(x: 0, y: height), end: .zero, options: [])
    let titleP = CGFloat(clamp01(s.intro / 0.4))
    text("12 costumes to collect", in: R(0, (vertical ? 150 : 82) + (1 - titleP) * 16, width, 70), size: vertical ? 40 : 54,
         weight: .heavy, align: .center, alpha: titleP)
    let tile: CGFloat = vertical ? 104 : 92, gap: CGFloat = 16, cols = vertical ? 3 : 6, gridTop: CGFloat = vertical ? 232 : 196
    let left = (width - (CGFloat(cols) * tile + CGFloat(cols - 1) * gap)) / 2
    for i in 0..<12 {
        let appear = s.intro - 0.35 - Double(i) * 0.09
        guard appear > 0 else { continue }
        let k = CGFloat(easeOutBack(clamp01(appear / 0.3)))
        let size = tile * k
        let cx = left + CGFloat(i % cols) * (tile + gap) + tile / 2
        let cy = gridTop + CGFloat(i / cols) * (tile + gap) + tile / 2
        roundedRect(c, R(cx - size / 2, cy - size / 2, size, size), 18 * k, fill: hex(0x2E1D4D), stroke: hex(0x5A3F86), line: 2.5)
        text("?", in: R(cx - size / 2, cy - 30 * k, size, 60 * k), size: 46 * k, weight: .black, color: orange, align: .center)
    }
    let subP = CGFloat(clamp01((s.intro - 1.8) / 0.4))
    text(vertical ? "Every pull is a surprise.\nWhich will you get?" : "Every pull is a surprise. Which will you get?",
         in: vertical ? R(40, 722, width - 80, 80) : R(0, 432, width, 36),
         size: vertical ? 25 : 26, weight: .semibold, color: lavender, align: .center, alpha: subP)
}

func render(_ s: Shot) -> CGContext {
    let c = makeContext()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
    switch s.mode {
    case .title: drawTitle(c, s, outro: false)
    case .outro: if vertical { drawOutroVertical(c, s) } else { drawTitle(c, s, outro: true) }
    case .collection: drawCollection(c, s)
    case .desktop: drawDesktop(c, s)
    }
    if s.dim > 0 {
        c.setFillColor(hex(0x000000, s.dim))
        c.fill(R(0, 0, width, height))
    }
    return c
}

// MARK: - Timeline

var s = Shot()
var states: [Shot] = []
var cues: [(name: String, time: Double, gain: Float)] = []
var now: Double { Double(states.count) / fps }

func frames(_ seconds: Double) -> Int { max(1, Int((seconds * fps).rounded())) }
func hold(_ seconds: Double) { for _ in 0..<frames(seconds) { tick() } }
func tick() {
    states.append(s)
    s.intro += 1 / fps
    s.flashes = s.flashes.compactMap { f in
        var f = f
        f.age += 1 / (fps * 1.1)
        return f.age < 1 ? f : nil
    }
}
func animate(_ seconds: Double, _ update: (Double) -> Void) {
    let n = frames(seconds)
    for i in 1...n { update(Double(i) / Double(n)); tick() }
}
func cue(_ name: String, gain: Float = 1, delay: Double = 0) { cues.append((name, now + delay, gain)) }
func mark(_ name: String) { FileHandle.standardError.write(String(format: "%6.2fs  %@\n", now, name).data(using: .utf8)!) }

func moveCursor(to target: CGPoint, _ seconds: Double) {
    let start = s.cursor
    animate(seconds) { p in
        let e = CGFloat(p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2)
        s.cursor = CGPoint(x: start.x + (target.x - start.x) * e, y: start.y + (target.y - start.y) * e)
    }
}

func rowCenter(_ index: Int) -> CGPoint {
    CGPoint(x: s.menuAt!.x + 110, y: s.menuAt!.y + rowTop(index) + rowHeight / 2)
}

func openMenu(on index: Int, travel: Double, wait: Double = 0.35) {
    let c = items[index].center
    moveCursor(to: CGPoint(x: c.x - 6, y: c.y + 6), travel)
    s.selected = index
    hold(0.18)
    let left = s.cursor.x - menuWidth - 4
    s.menuAt = CGPoint(x: left >= 8 ? left : s.cursor.x + 4, y: min(s.cursor.y, height - menuHeight - 20))
    hold(wait)
}

func choose(_ row: Int, travel: Double, wait: Double) {
    moveCursor(to: rowCenter(row), travel)
    hold(wait)
    s.menuAt = nil
}

/// The icon squashes, swaps to its new look, then springs back.
func popIcons(_ indices: [Int], dress: Bool, stagger: Double = 0) {
    let total = 0.42 + stagger * Double(indices.count - 1)
    animate(total) { p in
        let t = p * total
        for (n, i) in indices.enumerated() {
            let local = clamp01((t - stagger * Double(n)) / 0.42)
            if local >= 0.3 { if dress { s.dressed.insert(i) } else { s.dressed.remove(i) } }
            s.pop[i] = local < 0.3 ? CGFloat(1 - 0.35 * local / 0.3) : CGFloat(0.65 + 0.35 * easeOutBack((local - 0.3) / 0.7))
        }
    }
    for i in indices { s.pop[i] = nil }
}

func showCard(_ key: String) {
    s.card = key
    animate(0.35) { p in
        s.cardScale = CGFloat(0.6 + 0.4 * easeOutBack(p))
        s.cardAlpha = CGFloat(clamp01(p * 2))
    }
}

func hideCard() {
    animate(0.25) { p in s.cardAlpha = CGFloat(1 - p) }
    s.card = nil
    s.cardAlpha = 1
}

func fadeOut(_ seconds: Double = 0.4) { animate(seconds) { p in s.dim = CGFloat(p) } }
func fadeIn(_ seconds: Double = 0.4) { animate(seconds) { p in s.dim = CGFloat(1 - p) } }

// 1. Opening: a title card on YouTube; Shorts open straight on the Desktop with a hook.
s.dim = 1
cue("organ", gain: 0.9, delay: 0.15)
if vertical {
    mark("hook")
    s.mode = .desktop
    s.cursor = CGPoint(x: 250, y: 780)
    s.caption = "POV: your Mac's Desktop goes trick-or-treating 🎃"
    fadeIn(0.25)
    hold(1.8)
} else {
    mark("title")
    s.mode = .title
    animate(0.3) { p in s.dim = CGFloat(1 - p) }
    hold(3.2)
    fadeOut()
}

// 2. Hero demo: right-click → Trick or Treat → witch
mark("hero demo")
s.mode = .desktop
s.caption = "Right-click any file or folder on your Desktop"
if !vertical { fadeIn() }
hold(0.6)
openMenu(on: HOMEWORK, travel: 1.0)
s.caption = "Choose 🎃 Trick or Treat"
choose(5, travel: 0.7, wait: 0.7)
cue("ghost", gain: 0.85)
popIcons([HOMEWORK], dress: true)
showCard("homework")
s.caption = "It gets a surprise costume!"
hold(2.6)
hideCard()
s.selected = nil

// 3. Montage: every costume, files too
mark("montage")
s.caption = "Every pull is a surprise"
let montage: [(Int, String)] = [(1, "Vampire!"), (2, "Ghost!"), (3, "Jack-o'-Lantern!"), (4, "Mummy!"), (5, "Frankenstein!")]
for (n, (index, label)) in montage.enumerated() {
    openMenu(on: index, travel: n == 0 ? 0.5 : 0.38, wait: 0.2)
    choose(5, travel: 0.25, wait: 0.15)
    cue("pop", gain: 0.3)
    popIcons([index], dress: true)
    s.flashes.append(Flash(index: index, label: label, age: 0))
    s.selected = nil
    hold(n == 1 ? 0.7 : 0.35) // linger on the screenshot so its preview is visible
}
hold(0.5)

// 4. A Shiny pull
mark("shiny")
s.caption = "Rare golden Shinies ✨"
openMenu(on: PHOTOS, travel: 0.5)
choose(5, travel: 0.4, wait: 0.4)
cue("ghost", gain: 0.6)
cue("shiny", gain: 1, delay: 0.3)
popIcons([PHOTOS], dress: true)
showCard("photos")
hold(2.4)
hideCard()
s.selected = nil
hold(0.3)
fadeOut()

// 5. Collection teaser
mark("collection")
s.mode = .collection
s.intro = 0
fadeIn(0.3)
for i in 0..<12 { cue("tick", gain: 0.18, delay: 0.35 + Double(i) * 0.09 - 0.3) }
hold(3.6)
fadeOut()

// 6. Undecorate Desktop clears everything
mark("undecorate")
s.mode = .desktop
s.caption = "Undecorate anytime. Everything goes back exactly."
s.cursor = vertical ? CGPoint(x: 260, y: 780) : CGPoint(x: 600, y: 420)
fadeIn(0.3)
hold(0.5)
openMenu(on: 3, travel: 0.6)
choose(7, travel: 0.6, wait: 0.5)
mark("  click Undecorate Desktop")
s.selected = nil
cue("unpop", gain: 0.3)
popIcons(Array(0..<items.count), dress: false, stagger: 0.07)
showCard("undo")
hold(2.0)
hideCard()
hold(0.4)
fadeOut()

// 7. Outro
mark("outro")
s.mode = .outro
s.intro = 0
s.caption = ""
cue("bell", gain: 0.7, delay: 0.2)
fadeIn(0.3)
hold(4.6)
animate(0.6) { p in s.dim = CGFloat(p) }

let duration = now
mark("end")

// MARK: - Audio

let sampleRate = 44100.0

func loadSound(_ name: String) -> [Float] {
    guard let file = try? AVAudioFile(forReading: soundsDir.appendingPathComponent("\(name).m4a")),
          let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
          (try? file.read(into: buffer)) != nil, let data = buffer.floatChannelData else { return [] }
    return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
}

func synthPop(up: Bool) -> [Float] {
    let n = Int(0.16 * sampleRate)
    return (0..<n).map { i in
        let t = Double(i) / sampleRate, p = t / 0.16
        let f = up ? 420 + 900 * p : 1100 - 650 * p
        return Float(sin(2 * .pi * f * t) * exp(-t / 0.045) * 0.9)
    }
}

func synthTick() -> [Float] {
    let n = Int(0.09 * sampleRate)
    return (0..<n).map { i in
        let t = Double(i) / sampleRate
        return Float((sin(2 * .pi * 1760 * t) + 0.4 * sin(2 * .pi * 2640 * t)) * exp(-t / 0.025) * 0.6)
    }
}

/// Music-box melody over a plucked bass in D minor (i–VI–iv–V), synthesised from scratch.
func music(seconds: Double) -> [Float] {
    var out = [Float](repeating: 0, count: Int(seconds * sampleRate))
    let beat = 60.0 / 112
    func freq(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }
    func add(_ samples: [Float], at time: Double, gain: Float) {
        let start = Int(time * sampleRate)
        for (i, v) in samples.enumerated() where start + i < out.count { out[start + i] += v * gain }
    }
    var rng = UInt64(31)
    func noise() -> Double {
        rng = rng &* 6364136223846793005 &+ 1442695040888963407
        return Double(rng >> 33) / Double(1 << 31) - 1
    }
    func pluck(_ f: Double, _ length: Double) -> [Float] { // Karplus–Strong
        let period = Int(sampleRate / f)
        var ring = (0..<period).map { _ in noise() * 0.6 }
        var idx = 0
        return (0..<Int(length * sampleRate)).map { _ in
            let next = (idx + 1) % period
            let v = ring[idx]
            ring[idx] = 0.5 * (ring[idx] + ring[next]) * 0.994
            idx = next
            return Float(v)
        }
    }
    func bell(_ f: Double) -> [Float] {
        (0..<Int(0.9 * sampleRate)).map { i in
            let t = Double(i) / sampleRate
            let body = sin(2 * .pi * f * t) + 0.3 * sin(2 * .pi * f * 2.76 * t) * exp(-t / 0.12) + 0.12 * sin(2 * .pi * f * 5.4 * t) * exp(-t / 0.05)
            return Float(body * exp(-t / 0.35) * min(1, t / 0.003))
        }
    }
    let bass = [[50, 57, 62, 57], [46, 53, 58, 53], [43, 50, 55, 50], [45, 52, 57, 61]]
    let melody = [[69, 74, 77, 81, 79, 77, 76, 77], [74, 77, 82, 81, 79, 77, 74, 77],
                  [67, 70, 74, 79, 77, 74, 70, 74], [69, 73, 76, 81, 79, 76, 73, 76]]
    var bellCache: [Int: [Float]] = [:]
    var bar = 0
    var time = 0.0
    while time < seconds {
        let chord = bar % 4
        for (q, note) in bass[chord].enumerated() { add(pluck(freq(note), beat * 1.6), at: time + Double(q) * beat, gain: 0.55) }
        for (e, note) in melody[chord].enumerated() {
            if bellCache[note] == nil { bellCache[note] = bell(freq(note)) }
            add(bellCache[note]!, at: time + Double(e) * beat / 2, gain: e % 2 == 0 ? 0.32 : 0.24)
        }
        time += beat * 4
        bar += 1
    }
    return out
}

func writeAudio(to path: String) {
    let total = Int((duration + 0.5) * sampleRate)
    var mix = [Float](repeating: 0, count: total)
    func add(_ samples: [Float], at time: Double, gain: Float) {
        let start = Int(time * sampleRate)
        for (i, v) in samples.enumerated() where start + i < total && start + i >= 0 { mix[start + i] += v * gain }
    }

    // Music bed: enters after the title sting, ducks under the reveals, fades out at the end.
    let bed = music(seconds: duration)
    let musicStart = vertical ? 1.6 : 2.6, fadeOutStart = duration - 2.5
    for i in 0..<min(bed.count, total) {
        let t = Double(i) / sampleRate
        guard t >= musicStart else { continue }
        var g = min(1, (t - musicStart) / 1.0) * 0.32
        if t > fadeOutStart { g *= max(0, 1 - (t - fadeOutStart) / 2.5) }
        mix[i] += bed[i] * Float(g)
    }

    var library: [String: [Float]] = ["pop": synthPop(up: true), "unpop": synthPop(up: false), "tick": synthTick()]
    for name in ["organ", "ghost", "bell", "shiny"] { library[name] = loadSound(name) }
    for cue in cues {
        add(library[cue.name] ?? [], at: cue.time, gain: cue.gain)
    }

    let peak = mix.map(abs).max() ?? 1
    let norm = 0.89 / max(peak, 0.001)
    var pcm = Data()
    func le<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) } }
    pcm.append(contentsOf: "RIFF".utf8); le(UInt32(36 + total * 2)); pcm.append(contentsOf: "WAVEfmt ".utf8)
    le(UInt32(16)); le(UInt16(1)); le(UInt16(1)); le(UInt32(44100)); le(UInt32(88200)); le(UInt16(2)); le(UInt16(16))
    pcm.append(contentsOf: "data".utf8); le(UInt32(total * 2))
    for v in mix { le(Int16(max(-1, min(1, v * norm)) * 32767)) }
    try! pcm.write(to: URL(fileURLWithPath: path))
    FileHandle.standardError.write("audio: \(String(format: "%.1f", duration))s, \(cues.count) cues → \(path)\n".data(using: .utf8)!)
}

// MARK: - Output

if let i = args.firstIndex(of: "--audio") { writeAudio(to: args[i + 1]) }

if let i = args.firstIndex(of: "--stills") {
    let out = args[i + 1]
    let times = args[(i + 2)...].compactMap(Double.init)
    let cellW = pixelWidth / 3, cellH = pixelHeight / 3, cols = 3
    let rows = (times.count + cols - 1) / cols
    let sheet = makeContext(cellW * cols, cellH * rows, scale: 1)
    for (n, t) in times.enumerated() {
        let image = render(states[min(states.count - 1, Int(t * fps))]).makeImage()!
        sheet.draw(image, in: CGRect(x: (n % cols) * cellW, y: (rows - 1 - n / cols) * cellH, width: cellW, height: cellH))
    }
    try! NSBitmapImageRep(cgImage: sheet.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
    FileHandle.standardError.write("stills → \(out)\n".data(using: .utf8)!)
}

if let i = args.firstIndex(of: "--thumbnail") {
    // 1280×720 YouTube thumbnail: bold title on the left, big costumed folders on the right.
    let c = makeContext(1280, 720, scale: 1280 / width)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
    c.draw(wallpaper, in: R(0, 0, width, height))
    let shade = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [hex(0x07040D, 0.85), hex(0x07040D, 0)] as CFArray, locations: nil)!
    c.drawLinearGradient(shade, start: .zero, end: CGPoint(x: 560, y: 0), options: [])
    let cast: [(Costume, Bool, CGFloat, CGFloat, CGFloat)] = [
        (.witchHat, false, 575, 40, 205), (.vampire, true, 755, 70, 190), (.pumpkin, false, 585, 285, 190), (.ghost, false, 770, 300, 180),
    ]
    for (costume, shiny, x, y, size) in cast {
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: hex(0x000000, 0.55))
        c.draw(CostumeRenderer.render(costume, shiny: shiny, base: folderIcon), in: R(x, y, size, size))
        c.restoreGState()
    }
    text("MY DESKTOP", in: R(40, 120, 560, 80), size: 72, weight: .black)
    text("WENT TRICK", in: R(40, 196, 560, 80), size: 72, weight: .black, color: orange)
    text("OR TREATING", in: R(40, 272, 560, 80), size: 72, weight: .black, color: orange)
    text("🎃  free Mac app", in: R(44, 372, 520, 50), size: 34, weight: .bold, color: lavender)
    let rep = NSBitmapImageRep(cgImage: c.makeImage()!)
    try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!.write(to: URL(fileURLWithPath: args[i + 1]))
    FileHandle.standardError.write("thumbnail → \(args[i + 1])\n".data(using: .utf8)!)
}

if let i = args.firstIndex(of: "--guide") {
    // 1600×900 "Seeing a warning?" image to attach to posts: the same three clicks as the website.
    let c = makeContext(1600, 900, scale: 1600 / width)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
    let backdrop = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [hex(0x241540), hex(0x0B0614)] as CFArray, locations: nil)!
    c.drawLinearGradient(backdrop, start: CGPoint(x: 0, y: height), end: .zero, options: [])
    let ink = NSColor(red: 0.12, green: 0.05, blue: 0, alpha: 1)
    let soft = NSColor(red: 0.72, green: 0.71, blue: 0.76, alpha: 1)

    c.draw(appIcon, in: R(40, 34, 64, 64))
    text("Seeing a warning?", in: R(118, 36, 780, 50), size: 40, weight: .heavy)
    text("Trick or Treat is free, but not signed by Apple yet, so macOS asks you to confirm once. Three clicks:",
         in: R(120, 86, 800, 26), size: 17, weight: .medium, color: lavender)

    func button(_ label: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, style: String) {
        let fill: CGColor = style == "tap" ? orange.cgColor : style == "blue" ? hex(0x0A64D6) : hex(0x4A4752)
        if style == "tap" { roundedRect(c, R(x - 4, y - 4, w + 8, 36), 18, fill: hex(0xFF8F29, 0.35)) }
        roundedRect(c, R(x, y, w, 28), 14, fill: fill)
        text(label, in: R(x, y + 6, w, 18), size: 13, weight: .semibold, color: style == "tap" ? ink : .white, align: .center)
        if style == "tap" { text("👆", in: R(x + w - 14, y + 16, 30, 30), size: 22) }
    }
    func alert(_ x: CGFloat, title: String, body: String, buttons: [(String, String)]) {
        text("⚠️", in: R(x + 18, 182, 40, 36), size: 28)
        text(title, in: R(x + 18, 224, 250, 22), size: 15, weight: .bold)
        text(body, in: R(x + 18, 248, 250, 40), size: 12, color: soft)
        var bx = x + 18
        for (label, style) in buttons {
            button(label, bx, 306, 116, style: style)
            bx += 126
        }
    }

    let steps = ["1.  Click Done, not Move to Trash",
                 "2.  System Settings › Privacy & Security › Open Anyway",
                 "3.  Confirm with your password › Open Anyway"]
    for n in 0..<3 {
        let x = 40 + CGFloat(n) * 300
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: hex(0x000000, 0.5))
        roundedRect(c, R(x, 166, 280, 210), 18, fill: hex(0x2A2730), stroke: hex(0xFFFFFF, 0.14))
        c.restoreGState()
        switch n {
        case 0:
            alert(x, title: "“Trick or Treat” Not Opened", body: "Apple could not verify “Trick or Treat” is free of malware…",
                  buttons: [("Done", "tap"), ("Move to Trash", "blue")])
        case 1:
            for (row, label) in ["General", "Appearance", "Privacy & Security", "Desktop & Dock"].enumerated() {
                let y = 186 + CGFloat(row) * 28
                if row == 2 { roundedRect(c, R(x + 10, y - 4, 124, 24), 7, fill: hex(0x0A64D6)) }
                text(label, in: R(x + 17, y, 118, 18), size: 11, weight: row == 2 ? .semibold : .regular, color: row == 2 ? .white : soft)
            }
            text("Security", in: R(x + 146, 186, 124, 18), size: 12.5, weight: .bold)
            roundedRect(c, R(x + 142, 210, 128, 116), 10, fill: hex(0x34313B))
            text("“Trick or Treat” was blocked to protect your Mac.", in: R(x + 151, 220, 112, 60), size: 11.5,
                 color: NSColor(white: 0.86, alpha: 1))
            button("Open Anyway", x + 150, 284, 108, style: "tap")
        default:
            alert(x, title: "Open “Trick or Treat”?", body: "Confirm with your password or Touch ID.",
                  buttons: [("Open Anyway", "tap"), ("Done", "grey")])
        }
        text(steps[n], in: R(x + 2, 394, 280, 44), size: 15, weight: .semibold)
    }

    text("You only do this once. Free & open source:", in: R(0, 470, width, 24), size: 16, color: lavender, align: .center)
    text("angelwalia312.github.io/trickortreatyourdesktop", in: R(0, 494, width, 28), size: 20, weight: .bold, color: orange, align: .center)
    try! NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[i + 1]))
    FileHandle.standardError.write("guide → \(args[i + 1])\n".data(using: .utf8)!)
}

if args.contains("--frames") {
    let out = FileHandle.standardOutput
    for (n, state) in states.enumerated() {
        let c = render(state)
        out.write(Data(bytes: c.data!, count: pixelWidth * pixelHeight * 4))
        if n % 150 == 0 { FileHandle.standardError.write("frame \(n)/\(states.count)\n".data(using: .utf8)!) }
    }
}
