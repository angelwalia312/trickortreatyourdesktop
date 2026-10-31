import AppKit

/// The app's own icon: a jack-o'-lantern folder under a full moon, drawn by the costume renderer.
enum AppIcon {
    static func image() -> CGImage {
        let pumpkin = CostumeRenderer.render(.pumpkin, shiny: false, base: NSWorkspace.shared.icon(for: .folder))
        return CostumeRenderer.layer { c in
            let body = CGRect(x: 100, y: 100, width: 824, height: 824)
            let squircle = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
            c.shadowed(blur: 28, dy: -12, alpha: 0.4) {
                c.fill(squircle, linear: [hex(0x45297A), hex(0x150B2A)], from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))
            }

            c.saveGState()
            c.addPath(squircle)
            c.clip()
            let moon = CGPoint(x: 770, y: 790)
            c.drawRadialGradient(gradient([hex(0xFFE9A0, 0.5), hex(0xFFE9A0, 0)]), startCenter: moon, startRadius: 0,
                                 endCenter: moon, endRadius: 220, options: [])
            c.fill(ellipse(CGRect(x: moon.x - 70, y: moon.y - 70, width: 140, height: 140)),
                   radial: [hex(0xFFFBE0), hex(0xFFE58A)], center: CGPoint(x: moon.x - 22, y: moon.y + 22), radius: 100)
            for (x, y, r) in [(230, 830, 7), (340, 880, 4), (560, 870, 5), (190, 650, 4), (890, 600, 4), (450, 780, 3)] as [(CGFloat, CGFloat, CGFloat)] {
                c.fill(ellipse(CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), hex(0xFFFFFF, 0.85))
            }
            c.restoreGState()

            c.draw(pumpkin, in: CGRect(x: 147, y: 150, width: 730, height: 730))
        }
    }

    static func writeIconset(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let icon = image()
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = points * scale
                let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                ctx.interpolationQuality = .high
                ctx.draw(icon, in: CGRect(x: 0, y: 0, width: px, height: px))
                let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
                let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])
                try? png?.write(to: dir.appendingPathComponent(name))
            }
        }
    }
}
