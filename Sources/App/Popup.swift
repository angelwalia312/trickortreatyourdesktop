import AppKit
import SwiftUI

struct RevealItem: Identifiable {
    let id = UUID()
    let name: String
    let pull: Pull
    let isNew: Bool
    let icon: NSImage
}

enum Palette {
    static let pumpkin = Color(red: 1.0, green: 0.56, blue: 0.16)
    static let gold = Color(red: 1.0, green: 0.80, blue: 0.25)

    static func accent(_ pull: Pull) -> Color { pull.shiny ? gold : pumpkin }
}

/// Night-sky card background shared by the popup and the collection window.
struct SpookyBackground: View {
    var glow: Color = .purple

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.17, green: 0.10, blue: 0.28), Color(red: 0.07, green: 0.04, blue: 0.12)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [glow.opacity(0.45), .clear], center: .top, startRadius: 0, endRadius: 260)
        }
    }
}

struct HeaderBadge: View {
    let shiny: Bool

    var body: some View {
        Text(shiny ? "✦ SHINY ✦" : "🎃 TRICK OR TREAT!")
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(shiny ? Color(red: 0.36, green: 0.21, blue: 0) : .white)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(
                Capsule().fill(shiny
                    ? AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.95, blue: 0.6), Color(red: 1, green: 0.72, blue: 0.15)],
                                                   startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(Palette.pumpkin.opacity(0.85)))
            )
    }
}

/// Spinning light rays behind Shiny pulls.
struct Rays: View {
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = size.width / 2
            for i in 0..<12 {
                let a = Double(i) * .pi / 6
                var wedge = Path()
                wedge.move(to: c)
                wedge.addLine(to: CGPoint(x: c.x + r * cos(a - 0.13), y: c.y + r * sin(a - 0.13)))
                wedge.addLine(to: CGPoint(x: c.x + r * cos(a + 0.13), y: c.y + r * sin(a + 0.13)))
                wedge.closeSubpath()
                ctx.fill(wedge, with: .radialGradient(Gradient(colors: [color.opacity(0.75), color.opacity(0)]),
                                                      center: c, startRadius: 0, endRadius: r))
            }
        }
    }
}

struct NewTag: View {
    var body: some View {
        Text("NEW!")
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(Color(red: 1, green: 0.25, blue: 0.35)))
            .rotationEffect(.degrees(12))
            .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
    }
}

/// The reveal card that pops up after Trick or Treat.
struct RevealView: View {
    let items: [RevealItem]
    let collectedCount: Int
    @State private var shown: Bool
    @State private var spin = false

    init(items: [RevealItem], collectedCount: Int, animate: Bool = true) {
        self.items = items
        self.collectedCount = collectedCount
        _shown = State(initialValue: !animate)
    }

    private var anyShiny: Bool { items.contains { $0.pull.shiny } }
    private var accent: Color { anyShiny ? Palette.gold : Palette.pumpkin }

    var body: some View {
        VStack(spacing: 12) {
            HeaderBadge(shiny: anyShiny)
                .scaleEffect(shown ? 1 : 0.4)
                .opacity(shown ? 1 : 0)

            if items.count == 1 { single(items[0]) } else { grid }

            caption
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Collection \(collectedCount)/\(Pull.all.count)  ·  click to close")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 16)
        .frame(width: 300)
        .background(SpookyBackground(glow: accent))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(accent.opacity(anyShiny ? 0.95 : 0.5), lineWidth: anyShiny ? 3 : 1.5))
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.55)) { shown = true }
            withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) { spin = true }
        }
    }

    private func single(_ item: RevealItem) -> some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                if item.pull.shiny {
                    Rays(color: Palette.gold)
                        .frame(width: 250, height: 250)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .opacity(shown ? 1 : 0)
                }
                Image(nsImage: item.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 184, height: 184)
                    .scaleEffect(shown ? 1 : 0.15)
                    .rotationEffect(.degrees(shown ? 0 : -35))
            }
            .frame(width: 256, height: 196)
            .clipped()
            if item.isNew {
                NewTag().offset(x: -6, y: 6).scaleEffect(shown ? 1 : 0)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(78), spacing: 6), count: 3), spacing: 6) {
            ForEach(items.prefix(9)) { item in
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: item.icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 74, height: 74)
                        .background(Circle().fill(Palette.gold.opacity(item.pull.shiny ? 0.45 : 0)).blur(radius: 12))
                    if item.isNew {
                        Circle().fill(Color(red: 1, green: 0.25, blue: 0.35)).frame(width: 12, height: 12)
                    }
                }
                .scaleEffect(shown ? 1 : 0.2)
            }
        }
    }

    private var caption: Text {
        if items.count == 1, let item = items.first {
            return Text("“\(short(item.name))” is now a ")
                + Text(item.pull.title).bold().foregroundColor(Palette.accent(item.pull))
                + Text("!")
        }
        let extra = items.count > 9 ? " (+\(items.count - 9) more)" : ""
        let new = items.filter(\.isNew).count
        var text = Text("\(items.count) items dressed up\(extra)!")
        if let shiny = items.first(where: { $0.pull.shiny }) {
            text = text + Text("\nIncluding a ") + Text(shiny.pull.title).bold().foregroundColor(Palette.gold) + Text("!")
        }
        return new > 0 ? text + Text("\n\(new) new for your collection") : text
    }

    private func short(_ name: String) -> String {
        name.count > 22 ? name.prefix(20) + "…" : name
    }
}

struct NoticeView: View {
    let emoji: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(emoji).font(.system(size: 30))
            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .frame(width: 300, alignment: .leading)
        .background(SpookyBackground())
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 1))
    }
}

private final class ClickableHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A floating card near the pointer that never steals focus from Finder.
final class Popup {
    static let shared = Popup()
    private var panel: NSPanel?
    private var dismissal: DispatchWorkItem?

    func reveal(_ items: [RevealItem]) {
        let shiny = items.contains { $0.pull.shiny }
        present(RevealView(items: items, collectedCount: Gacha.shared.collected.count), seconds: shiny ? 5.5 : 4)
    }

    func notice(_ emoji: String, _ text: String) {
        present(NoticeView(emoji: emoji, text: text), seconds: 3)
    }

    private func present<V: View>(_ view: V, seconds: TimeInterval) {
        close(animated: false)
        let host = ClickableHostingView(rootView: view.onTapGesture { [weak self] in self?.close(animated: true) })
        let size = host.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        panel.setFrameOrigin(origin(for: size))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        let dismissal = DispatchWorkItem { [weak self] in self?.close(animated: true) }
        self.dismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: dismissal)
    }

    private func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = min(max(mouse.x + 28, area.minX + 12), area.maxX - size.width - 12)
        let y = min(max(mouse.y - size.height / 2, area.minY + 12), area.maxY - size.height - 12)
        return NSPoint(x: x, y: y)
    }

    func close(animated: Bool) {
        dismissal?.cancel()
        dismissal = nil
        guard let panel else { return }
        self.panel = nil
        guard animated else { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }
}
