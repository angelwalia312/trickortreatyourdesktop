import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = HomeModel()
    private let work = DispatchQueue(label: "com.trickortreat.work")
    private var home: NSWindow?
    private var openedByURL = false
    private var testMode = false
    private var idleQuit: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMenu()
        model.undressEverything = { [weak self] in self?.undressEverything() }
        if runDeveloperCommand() { return }
        // Launched by double-click rather than by the Finder extension: show the collection window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, !self.openedByURL else { return }
            self.showHome()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        openedByURL = true
        urls.forEach(handle)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showHome()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidBecomeActive(_ notification: Notification) { model.refresh() }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: Commands from the Finder extension

    private func handle(_ url: URL) {
        guard url.scheme == "trickortreat" else { return }
        let paths = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .filter { $0.name == "p" }.compactMap(\.value) ?? []
        // Whoever sent the link, only ever touch things on the Desktop.
        let targets = paths.map { URL(fileURLWithPath: $0) }.filter(Decorator.isOnDesktop)
        switch url.host {
        case "dress": dress(targets)
        case "undress": undress(targets)
        case "undress-desktop": undressDesktop()
        default: break
        }
        scheduleIdleQuit()
    }

    private func dress(_ targets: [URL]) {
        let skipAccessCheck = testMode
        work.async {
            guard skipAccessCheck || Decorator.canReadDesktop else {
                DispatchQueue.main.async {
                    Popup.shared.notice("🔒", "Trick or Treat needs access to your Desktop. Allow it in System Settings › Privacy & Security › Files & Folders.")
                }
                return
            }
            var items: [RevealItem] = []
            var failed = 0
            for url in targets where Decorator.isDressable(url) {
                guard let outcome = try? Decorator.dress(url) else { failed += 1; continue }
                items.append(RevealItem(name: url.lastPathComponent, pull: outcome.pull, isNew: outcome.isNew, icon: outcome.icon))
            }
            DispatchQueue.main.async {
                guard !items.isEmpty else {
                    if failed > 0 {
                        Popup.shared.notice("🔒", "That one wouldn't dress up. It might be locked or read-only.")
                    } else {
                        Popup.shared.notice("👻", "Apps and aliases can't go trick-or-treating. Try a file or folder!")
                    }
                    return
                }
                Popup.shared.reveal(items)
                Sounds.spooky()
                if items.contains(where: { $0.pull.shiny }) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { Sounds.sparkle() }
                }
                self.model.refresh()
            }
        }
    }

    private func undress(_ targets: [URL]) {
        work.async {
            let undressed = targets.filter { Decorator.undress($0) }
            DispatchQueue.main.async {
                switch undressed.count {
                case 0: Popup.shared.notice("🤷", "Nothing to take off. That isn't wearing a costume.")
                case 1: Popup.shared.notice("🧹", "Costume off! “\(undressed[0].lastPathComponent)” is back to normal.")
                default: Popup.shared.notice("🧹", "Costumes off! \(undressed.count) items are back to normal.")
                }
            }
        }
    }

    private func undressDesktop() {
        work.async {
            let count = Decorator.undressAll(under: Decorator.desktop)
            DispatchQueue.main.async {
                Popup.shared.notice("🧹", count == 0 ? "Your Desktop is already costume-free."
                    : "Undecorated \(count) item\(count == 1 ? "" : "s") on your Desktop.")
            }
        }
    }

    private func undressEverything() {
        work.async {
            let count = Decorator.undressAll(under: nil)
            DispatchQueue.main.async {
                Popup.shared.notice("🧹", count == 0 ? "Nothing is wearing a costume right now."
                    : "Undecorated \(count) item\(count == 1 ? "" : "s").")
            }
        }
    }

    // MARK: Windows

    private func showHome() {
        if home == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: HomeView(model: model)))
            window.title = "Trick or Treat"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            home = window
        }
        model.refresh()
        model.loadThumbnails()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        home?.makeKeyAndOrderFront(nil)
    }

    /// When launched just to handle a right-click, stay warm for a while, then get out of the way.
    private func scheduleIdleQuit() {
        idleQuit?.cancel()
        let item = DispatchWorkItem { [weak self] in
            if self?.home?.isVisible != true { NSApp.terminate(nil) }
        }
        idleQuit = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 15 * 60, execute: item)
    }

    private func makeMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "Quit Trick or Treat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(appItem)
        let windowItem = NSMenuItem()
        windowItem.submenu = NSMenu(title: "Window")
        windowItem.submenu?.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(windowItem)
        return main
    }

    // MARK: Developer commands (build script and testing only; not reachable from a link)

    private func runDeveloperCommand() -> Bool {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first, command.hasPrefix("--") else { return false }
        let rest = Array(args.dropFirst())
        switch command {
        case "--make-icon":
            AppIcon.writeIconset(to: URL(fileURLWithPath: rest[0]))
            exit(0)
        case "--render-reveal":
            renderPreview(revealSheet(), to: rest[0])
            exit(0)
        case "--render-card":
            // The single card shown on the website, at 2× for retina screens.
            let icon = CostumeRenderer.nsImage(CostumeRenderer.render(.witchHat, shiny: false, base: NSWorkspace.shared.icon(for: .folder)))
            let card = RevealView(items: [RevealItem(name: "Homework", pull: Pull(costume: .witchHat, shiny: false), isNew: true, icon: icon)],
                                  collectedCount: 4, animate: false)
            renderPreview(card, to: rest[0], scale: 2)
            exit(0)
        case "--render-home":
            model.extensionEnabled = false
            model.loadThumbnails(synchronously: true)
            renderPreview(HomeView(model: model), to: rest[0])
            exit(0)
        case "--test-dress", "--test-undress":
            testMode = true
            openedByURL = true
            Gacha.shared.store = UserDefaults(suiteName: "com.trickortreat.folders.tests")!
            let urls = rest.map { URL(fileURLWithPath: $0) }
            if command == "--test-dress" { dress(urls) } else { undress(urls) }
            // The work queue is serial, so this runs once the job above has finished.
            work.async { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { NSApp.terminate(nil) } }
            return true
        default:
            return false
        }
    }

    private func revealSheet() -> some View {
        let base = NSWorkspace.shared.icon(for: .folder)
        func item(_ costume: Costume, _ shiny: Bool, _ isNew: Bool, _ name: String) -> RevealItem {
            RevealItem(name: name, pull: Pull(costume: costume, shiny: shiny), isNew: isNew,
                       icon: CostumeRenderer.nsImage(CostumeRenderer.render(costume, shiny: shiny, base: base)))
        }
        return HStack(alignment: .top, spacing: 20) {
            RevealView(items: [item(.ghost, false, true, "Homework")], collectedCount: 3, animate: false)
            RevealView(items: [item(.vampire, true, true, "Taxes 2026")], collectedCount: 8, animate: false)
            RevealView(items: [item(.mummy, false, false, "a"), item(.pumpkin, false, true, "b"),
                               item(.frankenstein, false, true, "c"), item(.witchHat, false, false, "d")],
                       collectedCount: 6, animate: false)
            NoticeView(emoji: "🧹", text: "Undecorated 4 items on your Desktop.")
        }
        .padding(20)
        .background(Color(white: 0.85))
    }

    private func renderPreview<V: View>(_ view: V, to path: String, scale: CGFloat = 1) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
