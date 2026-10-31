import Cocoa
import FinderSync
import os

private let log = Logger(subsystem: "com.trickortreat.folders", category: "finder")

/// Adds the Trick or Treat items to Finder's right-click menus on the Desktop.
///
/// The extension is sandboxed and can't touch files itself, so each menu choice is handed to the
/// main app as a trickortreat:// link carrying the selected paths.
@objc(FinderSync)
final class FinderSync: FIFinderSync {
    private let home: URL = {
        // NSHomeDirectory() points into the sandbox container; ask for the real home folder.
        let path = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: path, isDirectory: true)
    }()

    private var desktop: URL { home.appendingPathComponent("Desktop", isDirectory: true) }

    override init() {
        super.init()
        // Watching the home folder too makes the Desktop a folder *inside* the watched area, which Finder
        // may need before it asks us for the empty-Desktop menu. Menus elsewhere are filtered out below.
        FIFinderSyncController.default().directoryURLs = [home, desktop]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let controller = FIFinderSyncController.default()
        let target = controller.targetedURL()
        log.info("menu kind=\(menuKind.rawValue, privacy: .public) target=\(target?.path ?? "nil", privacy: .public)")

        let menu = NSMenu(title: "")
        switch menuKind {
        case .contextualMenuForItems:
            let items = (controller.selectedItemURLs() ?? []).filter(isOnDesktop)
            guard !items.isEmpty else { return nil }
            menu.addItem(withTitle: "🎃 Trick or Treat", action: #selector(trickOrTreat(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "🧹 Undecorate", action: #selector(undecorate(_:)), keyEquivalent: "")
            // Also offered on Desktop items, so it's always reachable even if Finder skips the empty-Desktop menu.
            if items.contains(where: { isDesktop($0.deletingLastPathComponent()) }) {
                menu.addItem(withTitle: "🧹 Undecorate Desktop", action: #selector(undecorateDesktop(_:)), keyEquivalent: "")
            }
        case .contextualMenuForContainer:
            // Finder doesn't always say which folder was clicked when it's the Desktop itself.
            if let target, !isDesktop(target) { return nil }
            menu.addItem(withTitle: "🧹 Undecorate Desktop", action: #selector(undecorateDesktop(_:)), keyEquivalent: "")
        default:
            return nil
        }
        return menu
    }

    @IBAction func trickOrTreat(_ sender: AnyObject?) {
        send("dress", FIFinderSyncController.default().selectedItemURLs() ?? [])
    }

    @IBAction func undecorate(_ sender: AnyObject?) {
        send("undress", FIFinderSyncController.default().selectedItemURLs() ?? [])
    }

    @IBAction func undecorateDesktop(_ sender: AnyObject?) {
        send("undress-desktop", [])
    }

    private func isDesktop(_ url: URL) -> Bool {
        url.standardizedFileURL.path == desktop.standardizedFileURL.path
    }

    private func isOnDesktop(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(desktop.standardizedFileURL.path + "/")
    }

    private func send(_ action: String, _ urls: [URL]) {
        var components = URLComponents()
        components.scheme = "trickortreat"
        components.host = action
        if !urls.isEmpty {
            components.queryItems = urls.map { URLQueryItem(name: "p", value: $0.path) }
        }
        guard let link = components.url else { return }
        log.info("sending \(action, privacy: .public) for \(urls.count) item(s)")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.open(link, configuration: config, completionHandler: nil)
    }
}
