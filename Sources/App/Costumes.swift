import AppKit
import CoreGraphics

// MARK: - Catalogue

enum Costume: String, CaseIterable {
    case ghost, witchHat, pumpkin, mummy, vampire, frankenstein

    var displayName: String {
        switch self {
        case .ghost: return "Ghost"
        case .witchHat: return "Witch"
        case .pumpkin: return "Jack-o'-Lantern"
        case .mummy: return "Mummy"
        case .vampire: return "Vampire"
        case .frankenstein: return "Frankenstein"
        }
    }

    /// How large the folder is drawn (fraction of the canvas) and how far above the bottom edge it sits,
    /// leaving room for hats, collars and hair.
    fileprivate var layout: (scale: CGFloat, bottom: CGFloat) {
        switch self {
        case .ghost: return (0.84, 40)
        case .witchHat: return (0.74, 36)
        case .pumpkin: return (0.86, 52)
        case .mummy: return (0.84, 48)
        case .vampire: return (0.70, 70)
        case .frankenstein: return (0.76, 44)
        }
    }
}

// MARK: - Renderer

enum CostumeRenderer {
    static let size = 1024
    static let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)

    /// Dresses `base` (the folder's current icon) in `costume` and returns a 1024×1024 image.
    static func render(_ costume: Costume, shiny: Bool, base: NSImage) -> CGImage {
        let (folder, f) = place(base, costume.layout)
        let folderImg: CGImage
        switch costume {
        case .pumpkin where shiny: folderImg = recolor(folder, hue: hex(0xF2B90F), multiply: hex(0xFFE7A0))
        case .pumpkin: folderImg = recolor(folder, hue: hex(0xFF7A0C), multiply: hex(0xFFB65C))
        case .frankenstein: folderImg = recolor(folder, hue: hex(0x5DBB3F), multiply: hex(0xC8E6A8))
        default: folderImg = folder
        }

        var behind = layer { c in drawBehind(costume, c, f) }
        var front = layer { c in
            let masked = layer { drawMasked(costume, $0, f) }
            c.draw(mask(masked, by: folder), in: canvas)
            drawFront(costume, c, f)
        }
        if shiny {
            behind = goldify(behind)
            front = goldify(front)
        }

        return layer { c in
            if shiny { drawAura(c) }
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: hex(0x000000, 0.22))
            if shiny { c.setShadow(offset: .zero, blur: 46, color: hex(0xFFC830, 0.95)) }
            c.beginTransparencyLayer(auxiliaryInfo: nil)
            c.draw(behind, in: canvas)
            c.draw(folderImg, in: canvas)
            c.draw(front, in: canvas)
            c.endTransparencyLayer()
            c.restoreGState()
            if shiny { drawSparkles(c) }
        }
    }

    static func nsImage(_ img: CGImage) -> NSImage {
        NSImage(cgImage: img, size: NSSize(width: size, height: size))
    }

    /// Flattens an icon onto a 1024×1024 canvas, e.g. to save a folder's original look.
    static func snapshot(_ image: NSImage) -> CGImage {
        layer { draw(image, in: canvas, $0) }
    }

    // MARK: Folder placement

    /// Visible bounds of the stock folder icon on the canvas. Files are scaled to fill the same box so
    /// every costume keeps the headroom it was designed with.
    private static let referenceSize = CGSize(width: 957, height: 772)

    /// Draws the folder (or file) scaled down and bottom-anchored; returns it plus the frame to dress.
    private static func place(_ base: NSImage, _ layout: (scale: CGFloat, bottom: CGFloat)) -> (CGImage, Frame) {
        let full = layer { c in draw(base, in: canvas, c) }
        let b = alphaBounds(full) ?? canvas.insetBy(dx: 40, dy: 130)
        let s = layout.scale * min(referenceSize.width / b.width, referenceSize.height / b.height)
        let origin = CGPoint(x: canvas.midX - b.midX * s, y: layout.bottom - b.minY * s)
        let rect = CGRect(x: origin.x, y: origin.y, width: canvas.width * s, height: canvas.height * s)
        let folder = layer { c in draw(base, in: rect, c) }
        let body = CGRect(x: origin.x + b.minX * s, y: layout.bottom, width: b.width * s, height: b.height * s)
        return (folder, Frame(r: costumeFrame(in: body), body: body))
    }

    /// Costumes are designed for a folder's proportions. On very wide or very tall files they're drawn in a
    /// folder-shaped box at the top centre rather than stretched.
    private static func costumeFrame(in body: CGRect) -> CGRect {
        let aspect = body.width / body.height
        if aspect > 1.7 {
            let w = body.height * 1.7
            return CGRect(x: body.midX - w / 2, y: body.minY, width: w, height: body.height)
        }
        if aspect < 0.7 {
            let h = body.width / 0.7
            return CGRect(x: body.minX, y: body.maxY - h, width: body.width, height: h)
        }
        return body
    }

    /// Aspect-fits the image: icons are square, but previews of photos and screenshots usually aren't.
    private static func draw(_ image: NSImage, in rect: CGRect, _ c: CGContext) {
        let size = image.size
        let k = min(rect.width / max(size.width, 1), rect.height / max(size.height, 1))
        let fit = CGRect(x: rect.midX - size.width * k / 2, y: rect.midY - size.height * k / 2,
                         width: size.width * k, height: size.height * k)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
        image.draw(in: fit, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func alphaBounds(_ img: CGImage) -> CGRect? {
        let c = context()
        c.draw(img, in: canvas)
        guard let data = c.data?.bindMemory(to: UInt8.self, capacity: c.bytesPerRow * size) else { return nil }
        var minX = size, minY = size, maxX = -1, maxY = -1
        for row in 0..<size {
            for x in 0..<size where data[row * c.bytesPerRow + x * 4 + 3] > 40 {
                let y = size - 1 - row
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    // MARK: Layer helpers

    private static func context() -> CGContext {
        CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    static func layer(_ draw: (CGContext) -> Void) -> CGImage {
        let c = context()
        c.setLineJoin(.round)
        c.setLineCap(.round)
        draw(c)
        return c.makeImage()!
    }

    private static func mask(_ img: CGImage, by mask: CGImage) -> CGImage {
        layer { c in
            c.draw(img, in: canvas)
            c.setBlendMode(.destinationIn)
            c.draw(mask, in: canvas)
        }
    }

    /// Re-hues an image while keeping its shading, then deepens it with a multiply wash.
    private static func recolor(_ img: CGImage, hue: CGColor, multiply: CGColor) -> CGImage {
        layer { c in
            c.draw(img, in: canvas)
            c.setBlendMode(.color)
            c.setFillColor(hue)
            c.fill(canvas)
            c.setBlendMode(.multiply)
            c.setFillColor(multiply)
            c.fill(canvas)
            c.setBlendMode(.destinationIn)
            c.draw(img, in: canvas)
        }
    }

    /// Maps each pixel's brightness onto a gold ramp, lifting darks so black costume parts turn amber, not olive.
    private static func goldify(_ img: CGImage) -> CGImage {
        let c = context()
        c.draw(img, in: canvas)
        guard let d = c.data?.bindMemory(to: UInt8.self, capacity: c.bytesPerRow * size) else { return img }
        let stops: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.0, 0x3A, 0x20, 0x00), (0.35, 0xA0, 0x62, 0x06), (0.62, 0xEE, 0xB0, 0x18),
            (0.82, 0xFF, 0xDA, 0x52), (1.0, 0xFF, 0xF8, 0xDC),
        ]
        for row in 0..<size {
            for x in 0..<size {
                let i = row * c.bytesPerRow + x * 4
                let a = CGFloat(d[i + 3]) / 255
                guard a > 0 else { continue }
                let lum = (0.299 * CGFloat(d[i]) + 0.587 * CGFloat(d[i + 1]) + 0.114 * CGFloat(d[i + 2])) / 255 / a
                let t = min(1, 0.15 + 0.85 * lum)
                var k = 1
                while k < stops.count - 1 && stops[k].0 < t { k += 1 }
                let (t0, r0, g0, b0) = stops[k - 1], (t1, r1, g1, b1) = stops[k]
                let m = (t - t0) / (t1 - t0)
                d[i] = UInt8((r0 + (r1 - r0) * m) * a)
                d[i + 1] = UInt8((g0 + (g1 - g0) * m) * a)
                d[i + 2] = UInt8((b0 + (b1 - b0) * m) * a)
            }
        }
        return c.makeImage()!
    }

    // MARK: Shiny extras

    private static func drawAura(_ c: CGContext) {
        let center = CGPoint(x: canvas.midX, y: canvas.midY - 40)
        let g = gradient([hex(0xFFE27A, 0.55), hex(0xFFC93C, 0.25), hex(0xFFC93C, 0)], [0, 0.55, 1])
        c.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: 520, options: [])
        // Light rays
        c.saveGState()
        c.translateBy(x: center.x, y: center.y)
        for i in 0..<12 {
            let ray = CGMutablePath()
            ray.move(to: .zero)
            ray.addLine(to: CGPoint(x: -38, y: 540))
            ray.addLine(to: CGPoint(x: 38, y: 540))
            ray.closeSubpath()
            c.saveGState()
            c.rotate(by: CGFloat(i) * .pi / 6 + 0.12)
            c.fill(ray, hex(0xFFF1B8, 0.22))
            c.restoreGState()
        }
        c.restoreGState()
    }

    private static func drawSparkles(_ c: CGContext) {
        let spots: [(CGFloat, CGFloat, CGFloat)] = [
            (120, 880, 58), (905, 820, 46), (860, 170, 40), (150, 260, 34), (960, 520, 28), (520, 985, 30), (70, 560, 24),
        ]
        c.saveGState()
        c.setShadow(offset: .zero, blur: 18, color: hex(0xFFD24A, 1))
        for (x, y, r) in spots {
            let p = CGMutablePath()
            let k: CGFloat = 0.22
            p.move(to: CGPoint(x: x, y: y + r))
            p.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x + r * k, y: y + r * k))
            p.addQuadCurve(to: CGPoint(x: x, y: y - r), control: CGPoint(x: x + r * k, y: y - r * k))
            p.addQuadCurve(to: CGPoint(x: x - r, y: y), control: CGPoint(x: x - r * k, y: y - r * k))
            p.addQuadCurve(to: CGPoint(x: x, y: y + r), control: CGPoint(x: x - r * k, y: y + r * k))
            c.fill(p, radial: [hex(0xFFFFFF), hex(0xFFF3B0), hex(0xFFC53A)], center: CGPoint(x: x, y: y), radius: r)
        }
        c.restoreGState()
    }

    // MARK: Costume dispatch

    private static func drawBehind(_ costume: Costume, _ c: CGContext, _ f: Frame) {
        switch costume {
        case .vampire: Vampire.cape(c, f)
        case .frankenstein: Frankenstein.bolts(c, f)
        default: break
        }
    }

    private static func drawMasked(_ costume: Costume, _ c: CGContext, _ f: Frame) {
        switch costume {
        case .pumpkin: Pumpkin.ribs(c, f)
        case .mummy: Mummy.bandages(c, f)
        case .vampire: Vampire.hair(c, f)
        default: break
        }
    }

    private static func drawFront(_ costume: Costume, _ c: CGContext, _ f: Frame) {
        switch costume {
        case .ghost: Ghost.sheet(c, f)
        case .witchHat: WitchHat.hat(c, f)
        case .pumpkin: Pumpkin.face(c, f)
        case .mummy: Mummy.front(c, f)
        case .vampire: Vampire.face(c, f)
        case .frankenstein: Frankenstein.front(c, f)
        }
    }
}

// MARK: - Drawing primitives

/// Maps unit coordinates onto the costume box: u runs left→right, v bottom→top.
/// `body` is the item's full visible bounds, which can reach past the box on very wide or tall files.
struct Frame {
    let r: CGRect
    let body: CGRect
    /// The body's edges in unit coordinates (0 / 1 / 0 for a folder).
    var bodyLeft: CGFloat { (body.minX - r.minX) / r.width }
    var bodyRight: CGFloat { (body.maxX - r.minX) / r.width }
    var bodyBottom: CGFloat { (body.minY - r.minY) / r.height }
    func p(_ u: CGFloat, _ v: CGFloat) -> CGPoint { CGPoint(x: r.minX + u * r.width, y: r.minY + v * r.height) }
    func w(_ u: CGFloat) -> CGFloat { u * r.width }
    func h(_ v: CGFloat) -> CGFloat { v * r.height }
    /// Rect centred on (u, v) with the given unit width/height.
    func rect(_ u: CGFloat, _ v: CGFloat, _ du: CGFloat, _ dv: CGFloat) -> CGRect {
        CGRect(x: r.minX + (u - du / 2) * r.width, y: r.minY + (v - dv / 2) * r.height, width: du * r.width, height: dv * r.height)
    }
    /// Circle centred on (u, v) with radius given as a fraction of the folder width.
    func circle(_ u: CGFloat, _ v: CGFloat, _ radius: CGFloat) -> CGRect {
        let c = p(u, v), rad = w(radius)
        return CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2)
    }
}

let ink = hex(0x2A1A3A)
let inkWidth: CGFloat = 11

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

func ellipse(_ r: CGRect) -> CGPath { CGPath(ellipseIn: r, transform: nil) }

func polygon(_ f: Frame, _ pts: [(CGFloat, CGFloat)]) -> CGPath {
    let p = CGMutablePath()
    p.addLines(between: pts.map { f.p($0.0, $0.1) })
    p.closeSubpath()
    return p
}

extension CGContext {
    func fill(_ path: CGPath, _ color: CGColor) {
        saveGState(); addPath(path); setFillColor(color); fillPath(); restoreGState()
    }

    func fill(_ path: CGPath, linear colors: [CGColor], from: CGPoint, to: CGPoint, _ locations: [CGFloat]? = nil) {
        saveGState(); addPath(path); clip()
        drawLinearGradient(gradient(colors, locations), start: from, end: to,
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        restoreGState()
    }

    func fill(_ path: CGPath, radial colors: [CGColor], center: CGPoint, radius: CGFloat, _ locations: [CGFloat]? = nil) {
        saveGState(); addPath(path); clip()
        drawRadialGradient(gradient(colors, locations), startCenter: center, startRadius: 0, endCenter: center,
                           endRadius: radius, options: [.drawsAfterEndLocation])
        restoreGState()
    }

    func stroke(_ path: CGPath, _ color: CGColor = ink, _ width: CGFloat = inkWidth) {
        saveGState(); addPath(path); setStrokeColor(color); setLineWidth(width)
        setLineJoin(.round); setLineCap(.round); strokePath(); restoreGState()
    }

    /// Draws `body` as one group with a drop shadow, so clipped gradients still cast it.
    func shadowed(blur: CGFloat = 18, dy: CGFloat = -8, alpha: CGFloat = 0.3, _ body: () -> Void) {
        saveGState()
        setShadow(offset: CGSize(width: 0, height: dy), blur: blur, color: hex(0x000000, alpha))
        beginTransparencyLayer(auxiliaryInfo: nil)
        body()
        endTransparencyLayer()
        restoreGState()
    }
}

// MARK: - Costumes

private enum Ghost {
    static func sheet(_ c: CGContext, _ f: Frame) {
        let sheet = CGMutablePath()
        sheet.move(to: f.p(-0.07, 0.30))
        sheet.addCurve(to: f.p(0.5, 1.22), control1: f.p(-0.08, 0.95), control2: f.p(0.10, 1.22))
        sheet.addCurve(to: f.p(1.07, 0.30), control1: f.p(0.90, 1.22), control2: f.p(1.08, 0.95))
        let scallops = 5
        let span: CGFloat = 1.14 / CGFloat(scallops)
        for i in 0..<scallops {
            let x0 = 1.07 - CGFloat(i) * span, x1 = x0 - span
            let dip: CGFloat = i % 2 == 0 ? 0.10 : 0.14
            sheet.addQuadCurve(to: f.p(x1, 0.30), control: f.p((x0 + x1) / 2, dip))
        }
        sheet.closeSubpath()

        let eyes = [f.rect(0.36, 0.66, 0.115, 0.20), f.rect(0.64, 0.66, 0.115, 0.20)]

        c.saveGState()
        c.setAlpha(0.9)
        c.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: hex(0x1A1030, 0.35))
        c.beginTransparencyLayer(auxiliaryInfo: nil)

        c.fill(sheet, linear: [hex(0xFFFFFF), hex(0xF4F1FA), hex(0xDDD6EC)], from: f.p(0.5, 1.2), to: f.p(0.5, 0.2), [0, 0.5, 1])
        // Side shading for volume
        c.fill(sheet, linear: [hex(0xC9BEDF, 0), hex(0xC9BEDF, 0.55)], from: f.p(0.55, 0.6), to: f.p(1.07, 0.6))
        // Fabric folds falling into the hem
        for (top, bottom) in [((0.30, 0.95), (0.24, 0.30)), ((0.56, 1.0), (0.62, 0.28)), ((0.80, 0.85), (0.86, 0.30))] {
            let fold = CGMutablePath()
            fold.move(to: f.p(top.0, top.1))
            fold.addQuadCurve(to: f.p(bottom.0, bottom.1), control: f.p((top.0 + bottom.0) / 2 + 0.04, 0.6))
            c.saveGState(); c.addPath(sheet); c.clip()
            c.stroke(fold, hex(0x8C7FA8, 0.18), 16)
            c.restoreGState()
        }
        // Rosy cheeks
        c.fill(ellipse(f.rect(0.26, 0.50, 0.11, 0.06)), hex(0xFF8FB0, 0.35))
        c.fill(ellipse(f.rect(0.74, 0.50, 0.11, 0.06)), hex(0xFF8FB0, 0.35))
        c.stroke(sheet)

        // Eye holes: cut clean through so the folder shows underneath
        c.saveGState()
        c.setBlendMode(.clear)
        for e in eyes { c.fill(ellipse(e), hex(0x000000)) }
        c.restoreGState()
        for e in eyes {
            // Shadow of the cloth's thickness along the top of each hole
            let path = ellipse(e)
            c.fill(path, linear: [hex(0x1A1030, 0.55), hex(0x1A1030, 0)], from: CGPoint(x: e.midX, y: e.maxY), to: CGPoint(x: e.midX, y: e.midY + e.height * 0.05))
            c.stroke(path, ink, 10)
        }

        c.endTransparencyLayer()
        c.restoreGState()
    }
}

private enum WitchHat {
    static func hat(_ c: CGContext, _ f: Frame) {
        // Wavy orange hair spilling out from under the brim
        c.shadowed(blur: 10, dy: -4, alpha: 0.25) {
            let locks: [((CGFloat, CGFloat), (CGFloat, CGFloat), CGFloat)] = [
                ((0.10, 0.90), (-0.05, 0.52), -0.09), ((0.16, 0.88), (0.05, 0.56), -0.05), ((0.05, 0.88), (-0.07, 0.66), -0.08),
            ]
            for flip in [false, true] {
                for (a, b, bend) in locks {
                    let ua = flip ? 1 - a.0 : a.0, ub = flip ? 1 - b.0 : b.0, k = flip ? -bend : bend
                    let lock = CGMutablePath()
                    lock.move(to: f.p(ua, a.1))
                    lock.addCurve(to: f.p(ub, b.1), control1: f.p(ua + k, (a.1 * 2 + b.1) / 3), control2: f.p(ub - k, (a.1 + b.1 * 2) / 3))
                    c.stroke(lock, ink, 40)
                    c.stroke(lock, hex(0xFF8A2A), 26)
                    c.stroke(lock, hex(0xFFC27A, 0.6), 8)
                }
            }
        }
        // Happy closed eyes, cheeks and a little smile
        for u in [0.36, 0.64] as [CGFloat] {
            let eye = CGMutablePath()
            eye.move(to: f.p(u - 0.06, 0.45)); eye.addQuadCurve(to: f.p(u + 0.06, 0.45), control: f.p(u, 0.53))
            c.stroke(eye, ink, 12)
            c.fill(ellipse(f.rect(u + (u < 0.5 ? -0.07 : 0.07), 0.37, 0.09, 0.05)), hex(0xFF7FA6, 0.45))
        }
        let smile = CGMutablePath()
        smile.move(to: f.p(0.45, 0.32)); smile.addQuadCurve(to: f.p(0.55, 0.32), control: f.p(0.5, 0.26))
        c.stroke(smile, ink, 10)

        let tilt: CGFloat = -0.10
        let pivot = f.p(0.5, 0.92)
        c.saveGState()
        c.translateBy(x: pivot.x, y: pivot.y)
        c.rotate(by: tilt)
        c.translateBy(x: -pivot.x, y: -pivot.y)

        c.shadowed(blur: 22, dy: -14, alpha: 0.35) {
            // Brim
            let brim = ellipse(f.rect(0.5, 0.92, 1.06, 0.22))
            c.fill(brim, linear: [hex(0x5B3A86), hex(0x2B1745)], from: f.p(0.5, 1.03), to: f.p(0.5, 0.81))
            c.stroke(brim)

            // Cone with a crooked tip
            let cone = CGMutablePath()
            cone.move(to: f.p(0.23, 0.95))
            cone.addCurve(to: f.p(0.50, 1.50), control1: f.p(0.34, 1.12), control2: f.p(0.44, 1.38))
            cone.addCurve(to: f.p(0.90, 1.56), control1: f.p(0.58, 1.66), control2: f.p(0.80, 1.68))
            cone.addCurve(to: f.p(0.63, 1.40), control1: f.p(0.80, 1.52), control2: f.p(0.69, 1.48))
            cone.addCurve(to: f.p(0.77, 0.95), control1: f.p(0.62, 1.20), control2: f.p(0.70, 1.05))
            cone.addQuadCurve(to: f.p(0.23, 0.95), control: f.p(0.5, 0.86))
            cone.closeSubpath()
            c.fill(cone, linear: [hex(0x6C47A0), hex(0x3A2160), hex(0x24113D)], from: f.p(0.28, 1.2), to: f.p(0.78, 1.2), [0, 0.45, 1])

            // Orange band with a gold buckle
            c.saveGState()
            c.addPath(cone); c.clip()
            let band = CGMutablePath()
            band.move(to: f.p(0.1, 0.92))
            band.addQuadCurve(to: f.p(0.9, 0.92), control: f.p(0.5, 0.84))
            band.addLine(to: f.p(0.9, 1.06))
            band.addQuadCurve(to: f.p(0.1, 1.06), control: f.p(0.5, 0.99))
            band.closeSubpath()
            c.fill(band, linear: [hex(0xFFA43A), hex(0xE5650A)], from: f.p(0.5, 1.06), to: f.p(0.5, 0.88))
            c.stroke(band, ink, 8)
            c.restoreGState()
            let buckle = CGPath(roundedRect: f.rect(0.52, 0.965, 0.13, 0.10), cornerWidth: 8, cornerHeight: 8, transform: nil)
            c.stroke(buckle, hex(0xFFD54A), 16)
            c.stroke(CGPath(roundedRect: f.rect(0.52, 0.965, 0.13, 0.10).insetBy(dx: -8, dy: -8), cornerWidth: 14, cornerHeight: 14, transform: nil), ink, 5)
            c.stroke(CGPath(roundedRect: f.rect(0.52, 0.965, 0.13, 0.10).insetBy(dx: 8, dy: 8), cornerWidth: 4, cornerHeight: 4, transform: nil), ink, 5)

            // Highlight down the cone
            let shine = CGMutablePath()
            shine.move(to: f.p(0.33, 1.10))
            shine.addQuadCurve(to: f.p(0.47, 1.40), control: f.p(0.38, 1.30))
            c.stroke(shine, hex(0xFFFFFF, 0.28), 14)

            // Crescent moon decal
            let moon = CGMutablePath()
            moon.addEllipse(in: f.circle(0.55, 1.20, 0.045))
            c.fill(moon, hex(0xFFE36B))
            c.fill(ellipse(f.circle(0.575, 1.215, 0.04)), hex(0x3A2160))

            c.stroke(cone)
        }
        c.restoreGState()
    }
}

private enum Pumpkin {
    static func ribs(_ c: CGContext, _ f: Frame) {
        for (u, bend) in [(0.18, -0.07), (0.38, -0.03), (0.62, 0.03), (0.82, 0.07)] as [(CGFloat, CGFloat)] {
            let rib = CGMutablePath()
            rib.move(to: f.p(u, min(-0.05, f.bodyBottom - 0.05)))
            rib.addQuadCurve(to: f.p(u, 0.86), control: f.p(u + bend, 0.4))
            c.stroke(rib, hex(0xA83A00, 0.32), 18)
        }
        // Darker bottom for roundness
        c.fill(CGPath(rect: RectFromFrame(f), transform: nil), linear: [hex(0x7A2800, 0), hex(0x7A2800, 0.35)], from: f.p(0.5, 0.4), to: f.p(0.5, -0.02))
    }

    static func face(_ c: CGContext, _ f: Frame) {
        let leftEye = polygon(f, [(0.17, 0.47), (0.41, 0.49), (0.31, 0.69)])
        let rightEye = polygon(f, [(0.59, 0.49), (0.83, 0.47), (0.69, 0.69)])
        let nose = polygon(f, [(0.45, 0.37), (0.55, 0.37), (0.50, 0.46)])
        let mouth = polygon(f, [
            (0.13, 0.32), (0.26, 0.245), (0.33, 0.24), (0.33, 0.19), (0.41, 0.19), (0.41, 0.23),
            (0.59, 0.23), (0.59, 0.19), (0.67, 0.19), (0.67, 0.24), (0.74, 0.245), (0.87, 0.32),
            (0.80, 0.16), (0.66, 0.075), (0.56, 0.065), (0.56, 0.11), (0.46, 0.11), (0.46, 0.065),
            (0.34, 0.075), (0.20, 0.16),
        ])
        let cuts = [leftEye, rightEye, nose, mouth]
        let glow = [hex(0xFFFBD0), hex(0xFFD54A), hex(0xFF9800)]
        c.saveGState()
        c.setShadow(offset: .zero, blur: 34, color: hex(0xFFC400, 0.95))
        c.beginTransparencyLayer(auxiliaryInfo: nil)
        for cut in cuts {
            let b = cut.boundingBox
            c.fill(cut, radial: glow, center: CGPoint(x: b.midX, y: b.minY + b.height * 0.35), radius: max(b.width, b.height) * 0.7)
        }
        c.endTransparencyLayer()
        c.restoreGState()
        for cut in cuts { c.stroke(cut, hex(0x5C2200), 10) }

        // Stem, leaf and curly vine
        c.shadowed(blur: 12, dy: -6, alpha: 0.3) {
            let vine = CGMutablePath()
            vine.move(to: f.p(0.50, 0.95))
            vine.addCurve(to: f.p(0.36, 1.06), control1: f.p(0.44, 1.02), control2: f.p(0.34, 0.99))
            vine.addCurve(to: f.p(0.42, 1.10), control1: f.p(0.37, 1.12), control2: f.p(0.43, 1.12))
            c.stroke(vine, ink, 18)
            c.stroke(vine, hex(0x5FA83A), 9)

            let stem = CGMutablePath()
            stem.move(to: f.p(0.49, 0.86))
            stem.addCurve(to: f.p(0.54, 1.10), control1: f.p(0.49, 0.97), control2: f.p(0.51, 1.05))
            stem.addLine(to: f.p(0.63, 1.12))
            stem.addCurve(to: f.p(0.61, 0.86), control1: f.p(0.61, 1.02), control2: f.p(0.60, 0.94))
            stem.closeSubpath()
            c.fill(stem, linear: [hex(0x7A9A3A), hex(0x4E6A1E)], from: f.p(0.49, 1.0), to: f.p(0.62, 1.0))
            c.stroke(stem)

            let leaf = CGMutablePath()
            leaf.move(to: f.p(0.61, 0.93))
            leaf.addCurve(to: f.p(0.84, 1.03), control1: f.p(0.66, 1.06), control2: f.p(0.78, 1.08))
            leaf.addCurve(to: f.p(0.61, 0.93), control1: f.p(0.80, 0.94), control2: f.p(0.70, 0.90))
            leaf.closeSubpath()
            c.fill(leaf, linear: [hex(0x7CCB4F), hex(0x2F8A3A)], from: f.p(0.66, 1.05), to: f.p(0.8, 0.95))
            let vein = CGMutablePath()
            vein.move(to: f.p(0.63, 0.94)); vein.addQuadCurve(to: f.p(0.80, 1.02), control: f.p(0.72, 1.0))
            c.stroke(vein, hex(0x1F5A26, 0.6), 5)
            c.stroke(leaf)
        }
    }
}

private func RectFromFrame(_ f: Frame) -> CGRect { f.r.union(f.body).insetBy(dx: -f.r.width * 0.1, dy: -f.r.height * 0.1) }

private enum Mummy {
    static let bands: [(v: CGFloat, angle: CGFloat, thick: CGFloat)] = [
        (0.96, -0.05, 0.11), (0.84, 0.06, 0.105), (0.72, -0.03, 0.10),
        (0.40, 0.07, 0.105), (0.28, -0.05, 0.11), (0.16, 0.04, 0.10), (0.04, -0.06, 0.11),
    ]

    static func band(_ f: Frame, center: CGPoint, angle: CGFloat, length: CGFloat, thick: CGFloat) -> CGPath {
        var t = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
        let r = CGRect(x: -length / 2, y: -thick / 2, width: length, height: thick)
        return CGPath(roundedRect: r, cornerWidth: 6, cornerHeight: 6, transform: &t)
    }

    static func paint(_ c: CGContext, _ path: CGPath, _ f: Frame) {
        let b = path.boundingBox
        c.fill(path, linear: [hex(0xFBF5E4), hex(0xEDE2C6), hex(0xD5C59F)], from: CGPoint(x: b.midX, y: b.maxY), to: CGPoint(x: b.midX, y: b.minY), [0, 0.55, 1])
        // Weave texture
        c.saveGState(); c.addPath(path); c.clip()
        var x = b.minX - b.height
        while x < b.maxX {
            let l = CGMutablePath()
            l.move(to: CGPoint(x: x, y: b.minY)); l.addLine(to: CGPoint(x: x + b.height * 0.6, y: b.maxY))
            c.stroke(l, hex(0x9C8A62, 0.16), 4)
            x += 34
        }
        c.restoreGState()
        c.stroke(path, hex(0x6E5B3A), 6)
    }

    static func bandages(_ c: CGContext, _ f: Frame) {
        // Darkness behind the eye slit
        c.fill(CGPath(rect: f.rect(0.5, 0.565, 1.4, 0.24), transform: nil), linear: [hex(0x150B20, 0.0), hex(0x150B20, 0.55), hex(0x150B20, 0.0)], from: f.p(0.5, 0.69), to: f.p(0.5, 0.44))
        // Tall files get extra wraps further down.
        var wraps = bands
        var v: CGFloat = -0.08
        while v > f.bodyBottom - 0.1 {
            wraps.append((v, wraps.count % 2 == 0 ? 0.05 : -0.04, 0.105))
            v -= 0.12
        }
        let length = max(f.w(1.5), f.body.width * 1.3)
        for b in wraps {
            c.shadowed(blur: 10, dy: -5, alpha: 0.35) {
                paint(c, band(f, center: f.p(0.5, b.v), angle: b.angle, length: length, thick: f.h(b.thick)), f)
            }
        }
        // One diagonal wrap across the lower half
        c.shadowed(blur: 10, dy: -5, alpha: 0.35) {
            paint(c, band(f, center: f.p(0.58, 0.20), angle: 0.42, length: f.w(1.3), thick: f.h(0.10)), f)
        }
    }

    static func front(_ c: CGContext, _ f: Frame) {
        // Loose ends flapping off the edges
        c.shadowed(blur: 12, dy: -6, alpha: 0.3) {
            let tail = CGMutablePath()
            tail.move(to: f.p(0.95, 0.36))
            tail.addCurve(to: f.p(1.06, 0.06), control1: f.p(1.07, 0.33), control2: f.p(0.99, 0.14))
            tail.addLine(to: f.p(1.08, 0.02)); tail.addLine(to: f.p(1.09, 0.08)); tail.addLine(to: f.p(1.13, 0.07))
            tail.addCurve(to: f.p(0.97, 0.45), control1: f.p(1.07, 0.20), control2: f.p(1.12, 0.40))
            tail.closeSubpath()
            paint(c, tail, f)

            let flap = CGMutablePath()
            flap.move(to: f.p(0.04, 0.90))
            flap.addCurve(to: f.p(-0.06, 1.16), control1: f.p(-0.08, 0.96), control2: f.p(0.02, 1.08))
            flap.addLine(to: f.p(-0.02, 1.20)); flap.addLine(to: f.p(0.0, 1.15)); flap.addLine(to: f.p(0.04, 1.19))
            flap.addCurve(to: f.p(0.12, 0.92), control1: f.p(0.10, 1.10), control2: f.p(0.02, 1.0))
            flap.closeSubpath()
            paint(c, flap, f)
        }

        // Mismatched peeking eyes
        for (u, r, look) in [(0.38, 0.085, CGFloat(0.35)), (0.63, 0.066, CGFloat(0.35))] as [(CGFloat, CGFloat, CGFloat)] {
            let eye = f.circle(u, 0.565, r)
            c.shadowed(blur: 8, dy: -3, alpha: 0.35) {
                c.fill(ellipse(eye), radial: [hex(0xFFFFFF), hex(0xF1ECD8)], center: CGPoint(x: eye.midX - eye.width * 0.15, y: eye.midY + eye.height * 0.2), radius: eye.width * 0.6)
                c.stroke(ellipse(eye), ink, 9)
            }
            let pr = eye.width * 0.22
            let pc = CGPoint(x: eye.midX + eye.width * look * 0.6, y: eye.midY + eye.height * 0.08)
            c.fill(ellipse(CGRect(x: pc.x - pr, y: pc.y - pr, width: pr * 2, height: pr * 2)), hex(0x1A1020))
            c.fill(ellipse(CGRect(x: pc.x - pr * 0.1, y: pc.y + pr * 0.25, width: pr * 0.6, height: pr * 0.6)), hex(0xFFFFFF))
        }
    }
}

private enum Vampire {
    static func mirrored(_ f: Frame, _ pts: [(CGFloat, CGFloat)], build: (CGMutablePath, [CGPoint]) -> Void) -> [CGPath] {
        [false, true].map { flip in
            let p = CGMutablePath()
            build(p, pts.map { f.p(flip ? 1 - $0.0 : $0.0, $0.1) })
            p.closeSubpath()
            return p
        }
    }

    static func cape(_ c: CGContext, _ f: Frame) {
        c.shadowed(blur: 20, dy: -8, alpha: 0.35) {
            let body = CGMutablePath()
            body.move(to: f.p(0.06, 0.80))
            body.addCurve(to: f.p(-0.20, -0.08), control1: f.p(-0.06, 0.55), control2: f.p(-0.16, 0.25))
            body.addQuadCurve(to: f.p(0.5, -0.06), control: f.p(0.15, -0.02))
            body.addQuadCurve(to: f.p(1.20, -0.08), control: f.p(0.85, -0.02))
            body.addCurve(to: f.p(0.94, 0.80), control1: f.p(1.16, 0.25), control2: f.p(1.06, 0.55))
            body.closeSubpath()
            c.fill(body, linear: [hex(0x2B2036), hex(0x120C18)], from: f.p(0.5, 0.8), to: f.p(0.5, -0.1))
            c.stroke(body)

            // High popped collar: black outside, red lining inside
            let collars = mirrored(f, [(0.04, 0.58), (-0.19, 1.38), (0.24, 1.02), (0.30, 0.70)]) { p, q in
                p.move(to: q[0])
                p.addCurve(to: q[1], control1: CGPoint(x: q[0].x - f.w(0.18), y: q[0].y + f.h(0.30)), control2: CGPoint(x: q[1].x, y: q[1].y - f.h(0.35)))
                p.addCurve(to: q[2], control1: CGPoint(x: q[1].x + f.w(0.18), y: q[1].y - f.h(0.10)), control2: CGPoint(x: q[2].x - f.w(0.12), y: q[2].y + f.h(0.02)))
                p.addLine(to: q[3])
            }
            let linings = mirrored(f, [(0.10, 0.62), (-0.10, 1.27), (0.22, 0.98), (0.26, 0.72)]) { p, q in
                p.move(to: q[0])
                p.addCurve(to: q[1], control1: CGPoint(x: q[0].x - f.w(0.13), y: q[0].y + f.h(0.26)), control2: CGPoint(x: q[1].x, y: q[1].y - f.h(0.30)))
                p.addCurve(to: q[2], control1: CGPoint(x: q[1].x + f.w(0.14), y: q[1].y - f.h(0.10)), control2: CGPoint(x: q[2].x - f.w(0.10), y: q[2].y + f.h(0.02)))
                p.addLine(to: q[3])
            }
            for (collar, lining) in zip(collars, linings) {
                c.fill(collar, linear: [hex(0x2E2238), hex(0x0E0912)], from: f.p(0.5, 1.4), to: f.p(0.5, 0.6))
                c.stroke(collar)
                c.fill(lining, linear: [hex(0xE4334F), hex(0xA3132D), hex(0x6A0A1C)], from: f.p(0.5, 1.3), to: f.p(0.5, 0.65), [0, 0.5, 1])
                c.stroke(lining, ink, 7)
            }
        }
    }

    static func hair(_ c: CGContext, _ f: Frame) {
        let hair = CGMutablePath()
        hair.move(to: f.p(-0.1, 1.2))
        hair.addLine(to: f.p(-0.1, 0.70))
        hair.addCurve(to: f.p(0.5, 0.58), control1: f.p(0.18, 0.80), control2: f.p(0.40, 0.76))
        hair.addCurve(to: f.p(1.1, 0.70), control1: f.p(0.60, 0.76), control2: f.p(0.82, 0.80))
        hair.addLine(to: f.p(1.1, 1.2))
        hair.closeSubpath()
        c.fill(hair, linear: [hex(0x3A2E44), hex(0x16101C)], from: f.p(0.3, 1.0), to: f.p(0.6, 0.6))
        let shine = CGMutablePath()
        shine.move(to: f.p(0.12, 0.84))
        shine.addQuadCurve(to: f.p(0.40, 0.80), control: f.p(0.26, 0.88))
        c.stroke(shine, hex(0xFFFFFF, 0.28), 16)
        c.stroke(hair, ink, 14)
    }

    static func face(_ c: CGContext, _ f: Frame) {
        // Brows
        for (a, b) in [((0.19, 0.555), (0.43, 0.505)), ((0.81, 0.555), (0.57, 0.505))] {
            let brow = CGMutablePath()
            brow.move(to: f.p(a.0, a.1)); brow.addLine(to: f.p(b.0, b.1))
            c.stroke(brow, ink, 18)
        }
        // Almond eyes with glowing red irises
        for u in [0.31, 0.69] as [CGFloat] {
            let eye = CGMutablePath()
            eye.move(to: f.p(u - 0.10, 0.43))
            eye.addQuadCurve(to: f.p(u + 0.10, 0.43), control: f.p(u, 0.53))
            eye.addQuadCurve(to: f.p(u - 0.10, 0.43), control: f.p(u, 0.35))
            eye.closeSubpath()
            c.fill(eye, hex(0xFFFFFF))
            c.saveGState(); c.addPath(eye); c.clip()
            let iris = f.circle(u + 0.01, 0.435, 0.04)
            c.fill(ellipse(iris), radial: [hex(0xFF5A6E), hex(0xC0102E)], center: CGPoint(x: iris.midX, y: iris.midY), radius: iris.width / 2)
            c.fill(ellipse(f.circle(u + 0.01, 0.435, 0.017)), hex(0x1A0A10))
            c.fill(ellipse(f.circle(u + 0.025, 0.45, 0.009)), hex(0xFFFFFF))
            c.restoreGState()
            c.stroke(eye, ink, 9)
        }
        // Smirk and fangs
        let mouth = CGMutablePath()
        mouth.move(to: f.p(0.34, 0.26))
        mouth.addQuadCurve(to: f.p(0.66, 0.26), control: f.p(0.5, 0.19))
        for u in [0.43, 0.57] as [CGFloat] {
            let fang = polygon(f, [(u - 0.035, 0.232), (u + 0.035, 0.232), (u, 0.14)])
            c.fill(fang, hex(0xFFFFFF))
            c.stroke(fang, ink, 7)
        }
        c.stroke(mouth, ink, 11)
    }
}

private enum Frankenstein {
    static func bolts(_ c: CGContext, _ f: Frame) {
        for flip in [false, true] {
            // Bolts stick out of the item's real sides, even when it's wider than the costume box.
            let u: (CGFloat) -> CGFloat = { flip ? f.bodyRight - $0 : f.bodyLeft + $0 }
            c.shadowed(blur: 10, dy: -5, alpha: 0.3) {
                let shaft = CGPath(rect: f.rect(u(-0.04), 0.30, 0.22, 0.07), transform: nil)
                c.fill(shaft, linear: [hex(0xD8DEE6), hex(0x8D96A3), hex(0x5B6470)], from: f.p(0.5, 0.335), to: f.p(0.5, 0.265), [0, 0.5, 1])
                c.stroke(shaft, ink, 8)
                let nut = CGPath(roundedRect: f.rect(u(-0.14), 0.30, 0.06, 0.15), cornerWidth: 6, cornerHeight: 6, transform: nil)
                c.fill(nut, linear: [hex(0xB8C0CC), hex(0x6B7480), hex(0x454C56)], from: f.p(0.5, 0.375), to: f.p(0.5, 0.225), [0, 0.5, 1])
                c.stroke(nut, ink, 8)
            }
        }
    }

    static func front(_ c: CGContext, _ f: Frame) {
        // Flat-top hair with jagged bangs
        c.shadowed(blur: 14, dy: -8, alpha: 0.4) {
            let hair = CGMutablePath()
            hair.move(to: f.p(-0.03, 1.12))
            hair.addLine(to: f.p(1.03, 1.12))
            hair.addLine(to: f.p(1.03, 0.80))
            let teeth = 11
            for i in 0..<teeth {
                let x0 = 1.03 - CGFloat(i) * 1.06 / CGFloat(teeth)
                let x1 = x0 - 1.06 / CGFloat(teeth)
                hair.addLine(to: f.p((x0 + x1) / 2, i % 3 == 1 ? 0.66 : 0.70))
                hair.addLine(to: f.p(x1, 0.80))
            }
            hair.closeSubpath()
            c.fill(hair, linear: [hex(0x3A3438), hex(0x141014)], from: f.p(0.5, 1.12), to: f.p(0.5, 0.7))
            for v in [1.04, 0.95] as [CGFloat] {
                let streak = CGMutablePath()
                streak.move(to: f.p(0.08, v)); streak.addLine(to: f.p(0.55, v))
                c.stroke(streak, hex(0xFFFFFF, 0.14), 10)
            }
            c.stroke(hair)
        }

        // Forehead scar
        let scar = CGMutablePath()
        scar.move(to: f.p(0.56, 0.62)); scar.addLine(to: f.p(0.88, 0.58))
        c.stroke(scar, ink, 8)
        for i in 0..<5 {
            let t = CGFloat(i) / 4
            let x = 0.59 + t * 0.26, y = 0.616 - t * 0.032
            let tick = CGMutablePath()
            tick.move(to: f.p(x - 0.01, y + 0.035)); tick.addLine(to: f.p(x + 0.01, y - 0.035))
            c.stroke(tick, ink, 7)
        }

        // Sleepy eyes
        for u in [0.34, 0.66] as [CGFloat] {
            let e = f.circle(u, 0.44, 0.075)
            c.fill(ellipse(e), hex(0xFFFFFF))
            c.fill(ellipse(f.circle(u + 0.005, 0.425, 0.028)), hex(0x1A1020))
            c.saveGState(); c.addPath(ellipse(e)); c.clip()
            let lid = CGPath(rect: CGRect(x: e.minX, y: e.midY + e.height * 0.02, width: e.width, height: e.height), transform: nil)
            c.fill(lid, linear: [hex(0x6FA84E), hex(0x4C7F35)], from: CGPoint(x: e.midX, y: e.maxY), to: CGPoint(x: e.midX, y: e.midY))
            c.restoreGState()
            let lidLine = CGMutablePath()
            lidLine.move(to: CGPoint(x: e.minX, y: e.midY + e.height * 0.02)); lidLine.addLine(to: CGPoint(x: e.maxX, y: e.midY + e.height * 0.02))
            c.stroke(lidLine, ink, 8)
            c.stroke(ellipse(e), ink, 9)
        }

        // Stitched mouth
        let mouth = CGMutablePath()
        mouth.move(to: f.p(0.35, 0.22)); mouth.addLine(to: f.p(0.65, 0.22))
        c.stroke(mouth, ink, 11)
        for u in [0.42, 0.5, 0.58] as [CGFloat] {
            let s = CGMutablePath()
            s.move(to: f.p(u, 0.18)); s.addLine(to: f.p(u, 0.26))
            c.stroke(s, ink, 7)
        }
    }
}
