import AppKit
import UniformTypeIdentifiers

// Costume previews and website images, drawn with the app's own renderer.
//
//   preview sheet.png            contact sheet of every costume (normal + Shiny, plus small sizes)
//   preview --site docs/         per-costume PNGs and the social card used by the website

let base = NSWorkspace.shared.icon(for: .folder)

func writePNG(_ image: CGImage, _ path: String) {
    let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: path))
}

func makeContext(_ width: Int, _ height: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    return ctx
}

func scaled(_ image: CGImage, _ px: Int) -> CGImage {
    let ctx = makeContext(px, px)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: px, height: px))
    return ctx.makeImage()!
}

func contactSheet(_ out: String) {
    let cell = 320, small = [64, 32]
    let width = Costume.allCases.count * cell, height = cell * 2 + 80
    let ctx = makeContext(width, height)
    ctx.setFillColor(CGColor(srgbRed: 0.93, green: 0.93, blue: 0.95, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for (i, costume) in Costume.allCases.enumerated() {
        for (row, shiny) in [false, true].enumerated() {
            let img = CostumeRenderer.render(costume, shiny: shiny, base: base)
            ctx.draw(img, in: CGRect(x: i * cell, y: height - (row + 1) * cell, width: cell, height: cell))
            guard !shiny else { continue }
            var x = i * cell + 20
            for s in small {
                ctx.draw(img, in: CGRect(x: x, y: 8, width: s, height: s))
                x += s + 16
            }
        }
    }
    writePNG(ctx.makeImage()!, out)
}

func siteImages(_ dir: String) {
    var renders: [Costume: CGImage] = [:]
    for costume in Costume.allCases {
        let img = CostumeRenderer.render(costume, shiny: false, base: base)
        renders[costume] = img
        writePNG(scaled(img, 400), "\(dir)/costume-\(costume.rawValue).png")
    }
    writePNG(scaled(CostumeRenderer.render(.vampire, shiny: true, base: base), 400), "\(dir)/costume-shiny.png")

    // 1200×630 card shown when the link is shared on Twitter, iMessage, Slack…
    let w = 1200, h = 630
    let ctx = makeContext(w, h)
    let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                        colors: [hex(0x2C1A47), hex(0x0D0718)] as CFArray, locations: nil)!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: h), end: .zero, options: [])
    let moon = CGPoint(x: 1060, y: 520)
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [hex(0xFFE9A0, 0.45), hex(0xFFE9A0, 0)] as CFArray, locations: nil)!
    ctx.drawRadialGradient(glow, startCenter: moon, startRadius: 0, endCenter: moon, endRadius: 220, options: [])
    ctx.setFillColor(hex(0xFFF3C0))
    ctx.fillEllipse(in: CGRect(x: moon.x - 52, y: moon.y - 52, width: 104, height: 104))

    let order: [Costume] = [.ghost, .witchHat, .pumpkin, .mummy, .vampire, .frankenstein]
    for (i, costume) in order.enumerated() {
        ctx.draw(renders[costume]!, in: CGRect(x: 40 + i * 188, y: 40, width: 180, height: 180))
    }

    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let title = NSAttributedString(string: "Trick or Treat", attributes: [
        .font: NSFont.systemFont(ofSize: 96, weight: .black), .foregroundColor: NSColor.white])
    title.draw(at: NSPoint(x: 64, y: 380))
    let sub = NSAttributedString(string: "Right-click anything on your Mac's Desktop.\nIt gets a surprise Halloween costume.", attributes: [
        .font: NSFont.systemFont(ofSize: 34, weight: .semibold), .foregroundColor: NSColor(red: 1, green: 0.7, blue: 0.4, alpha: 1)])
    sub.draw(at: NSPoint(x: 68, y: 262))
    writePNG(ctx.makeImage()!, "\(dir)/social-card.png")
}

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "--site", args.count > 1 {
    siteImages(args[1])
    print("wrote website images to \(args[1])")
} else {
    let out = args.first ?? "preview.png"
    contactSheet(out)
    print("wrote \(out)")
}
