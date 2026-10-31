import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Puts costumes on files and folders and takes them off again, restoring exactly what was there before.
///
/// A costume is a custom icon, so a file's contents are never touched. Each dressed item carries two extended
/// attributes: the costume it's wearing and the id of a backup (in Application Support) holding its original
/// look. The attributes travel with the item if it's moved.
enum Decorator {
    struct Outcome {
        let item: URL
        let pull: Pull
        let isNew: Bool
        let icon: NSImage
    }

    enum Failure: Error { case notDressable, couldNotSetIcon }

    private static let costumeAttr = "com.trickortreat.costume"
    private static let idAttr = "com.trickortreat.id"
    private static let resourceForkAttr = "com.apple.ResourceFork"
    private static let iconOptions: NSWorkspace.IconCreationOptions = .excludeQuickDrawElementsIconCreationOption

    static let desktop = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop", isDirectory: true).resolvingSymlinksInPath()

    /// Plain files and folders. Apps and other bundles are left alone (a new icon would break their code
    /// signature), and so are aliases and symlinks, which borrow their icon from what they point to.
    static func isDressable(_ url: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isPackageKey, .isAliasFileKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isPackage != true, values.isAliasFile != true else { return false }
        return values.isDirectory == true || values.isRegularFile == true
    }

    static func isOnDesktop(_ url: URL) -> Bool {
        url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(desktop.path + "/")
    }

    static var canReadDesktop: Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: desktop.path)) != nil
    }

    static func isDressed(_ url: URL) -> Bool { attr(url, costumeAttr) != nil }

    static func dress(_ item: URL) throws -> Outcome {
        guard isDressable(item) else { throw Failure.notDressable }

        let backup: Backup
        let isFirstCostume: Bool
        if let id = attr(item, idAttr), let saved = Backup.load(id: id) {
            backup = saved
            isFirstCostume = false
        } else {
            // A costume with no backup (e.g. a copied item) means its current icon can't be trusted.
            let orphaned = isDressed(item)
            let hadCustomIcon = !orphaned && hasCustomIcon(item)
            let look = currentLook(of: item, orphaned: orphaned, hadCustomIcon: hadCustomIcon)
            backup = try Backup.create(base: CostumeRenderer.snapshot(look), hadCustomIcon: hadCustomIcon,
                                       hadResourceFork: rawAttr(item, resourceForkAttr) != nil)
            isFirstCostume = true
        }

        let current = attr(item, costumeAttr).flatMap(Pull.init(id:))?.costume
        let (pull, isNew) = Gacha.shared.roll(avoiding: current)
        let icon = CostumeRenderer.nsImage(CostumeRenderer.render(pull.costume, shiny: pull.shiny, base: backup.baseImage))
        guard keepingModificationDate(of: item, { NSWorkspace.shared.setIcon(icon, forFile: item.path, options: iconOptions) }) else {
            if isFirstCostume { backup.delete() }
            throw Failure.couldNotSetIcon
        }
        setAttr(item, idAttr, backup.id)
        setAttr(item, costumeAttr, pull.id)
        backup.record(path: item.path)
        NSWorkspace.shared.noteFileSystemChanged(item.path)
        return Outcome(item: item, pull: pull, isNew: isNew, icon: icon)
    }

    @discardableResult
    static func undress(_ item: URL) -> Bool {
        guard isDressed(item) else { return false }
        let backup = attr(item, idAttr).flatMap(Backup.load(id:))
        _ = keepingModificationDate(of: item) {
            if let backup, backup.hadCustomIcon {
                return NSWorkspace.shared.setIcon(backup.baseImage, forFile: item.path, options: iconOptions)
            }
            let cleared = NSWorkspace.shared.setIcon(nil, forFile: item.path, options: [])
            // Clearing an icon leaves an empty resource fork behind on files; drop it if there wasn't one before.
            if backup?.hadResourceFork == false { removeAttr(item, resourceForkAttr) }
            return cleared
        }
        removeAttr(item, idAttr)
        removeAttr(item, costumeAttr)
        backup?.delete()
        NSWorkspace.shared.noteFileSystemChanged(item.path)
        return true
    }

    /// Undresses every costumed item under `root`, or every one we know of when `root` is nil.
    static func undressAll(under root: URL?) -> Int {
        var count = 0
        // Items we remember dressing, including ones nested in subfolders.
        for backup in Backup.all() {
            guard let path = backup.path else { continue }
            if let root, !path.hasPrefix(root.path + "/") { continue }
            let url = URL(fileURLWithPath: path)
            if attr(url, idAttr) == backup.id {
                if undress(url) { count += 1 }
            } else if root == nil {
                backup.delete() // Item was moved or deleted; forget it.
            }
        }
        // Anything else still dressed at the top level (e.g. copies of costumed items).
        if let root, let items = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for url in items where isDressed(url) && undress(url) { count += 1 }
        }
        return count
    }

    /// What the item looks like on the Desktop right now: its custom icon if it has one, a folder icon for
    /// folders, otherwise Finder's preview (a screenshot shows the screenshot, a PDF its first page).
    private static func currentLook(of item: URL, orphaned: Bool, hadCustomIcon: Bool) -> NSImage {
        let isFolder = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        if isFolder { return orphaned ? NSWorkspace.shared.icon(for: .folder) : NSWorkspace.shared.icon(forFile: item.path) }
        if hadCustomIcon { return NSWorkspace.shared.icon(forFile: item.path) }

        let request = QLThumbnailGenerator.Request(fileAt: item, size: CGSize(width: 512, height: 512), scale: 2,
                                                   representationTypes: .all)
        var preview: NSImage?
        let done = DispatchSemaphore(value: 0)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            if let representation {
                preview = representation.type == .icon ? representation.nsImage : framed(representation.nsImage)
            }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 5)
        return preview ?? NSWorkspace.shared.icon(forFile: item.path)
    }

    /// Finder draws previews on a white card with a hairline edge; without it a white page vanishes on the Desktop.
    private static func framed(_ image: NSImage) -> NSImage {
        let pad = max(image.size.width, image.size.height) * 0.03
        let size = NSSize(width: image.size.width + pad * 2, height: image.size.height + pad * 2)
        return NSImage(size: size, flipped: false) { rect in
            let card = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: pad, yRadius: pad)
            NSColor.white.setFill()
            card.fill()
            image.draw(in: rect.insetBy(dx: pad, dy: pad))
            NSColor(white: 0, alpha: 0.2).setStroke()
            card.lineWidth = 1.5
            card.stroke()
            return true
        }
    }

    /// Changing an icon bumps the modification date, which would reshuffle a Desktop sorted by date.
    private static func keepingModificationDate(of item: URL, _ change: () -> Bool) -> Bool {
        let date = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let result = change()
        if let date {
            var values = URLResourceValues()
            values.contentModificationDate = date
            var url = item
            try? url.setResourceValues(values)
        }
        return result
    }

    private static func hasCustomIcon(_ item: URL) -> Bool {
        if FileManager.default.fileExists(atPath: item.appendingPathComponent("Icon\r").path) { return true }
        // Finder flags are big-endian at bytes 8–9; kHasCustomIcon is 0x0400.
        guard let info = rawAttr(item, "com.apple.FinderInfo"), info.count >= 10 else { return false }
        return info[8] & 0x04 != 0
    }

    // MARK: Extended attributes

    private static func rawAttr(_ url: URL, _ name: String) -> [UInt8]? {
        url.withUnsafeFileSystemRepresentation { path -> [UInt8]? in
            guard let path else { return nil }
            let length = getxattr(path, name, nil, 0, 0, 0)
            guard length > 0 else { return nil }
            var buffer = [UInt8](repeating: 0, count: length)
            guard getxattr(path, name, &buffer, length, 0, 0) == length else { return nil }
            return buffer
        }
    }

    private static func attr(_ url: URL, _ name: String) -> String? {
        rawAttr(url, name).map { String(decoding: $0, as: UTF8.self) }
    }

    private static func setAttr(_ url: URL, _ name: String, _ value: String) {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            let bytes = Array(value.utf8)
            _ = setxattr(path, name, bytes, bytes.count, 0, 0)
        }
    }

    private static func removeAttr(_ url: URL, _ name: String) {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = removexattr(path, name, 0)
        }
    }
}

/// An item's original look, saved before its first costume.
private struct Backup {
    let id: String
    let hadCustomIcon: Bool
    let hadResourceFork: Bool
    let path: String?

    private var dir: URL { Self.root.appendingPathComponent(id, isDirectory: true) }

    var baseImage: NSImage {
        NSImage(contentsOf: dir.appendingPathComponent("base.png")) ?? NSWorkspace.shared.icon(for: .folder)
    }

    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Trick or Treat/Backups", isDirectory: true)
    }

    static func create(base: CGImage, hadCustomIcon: Bool, hadResourceFork: Bool) throws -> Backup {
        let backup = Backup(id: UUID().uuidString, hadCustomIcon: hadCustomIcon, hadResourceFork: hadResourceFork, path: nil)
        try FileManager.default.createDirectory(at: backup.dir, withIntermediateDirectories: true)
        guard let png = NSBitmapImageRep(cgImage: base).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: backup.dir.appendingPathComponent("base.png"))
        backup.writeMeta()
        return backup
    }

    static func load(id: String) -> Backup? {
        let dir = root.appendingPathComponent(id, isDirectory: true)
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("meta.plist")),
              let meta = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return Backup(id: id, hadCustomIcon: meta["hadCustomIcon"] as? Bool ?? false,
                      hadResourceFork: meta["hadResourceFork"] as? Bool ?? true, path: meta["path"] as? String)
    }

    static func all() -> [Backup] {
        let ids = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return ids.compactMap(load(id:))
    }

    func record(path: String) {
        Backup(id: id, hadCustomIcon: hadCustomIcon, hadResourceFork: hadResourceFork, path: path).writeMeta()
    }

    func delete() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func writeMeta() {
        var meta: [String: Any] = ["hadCustomIcon": hadCustomIcon, "hadResourceFork": hadResourceFork]
        meta["path"] = path
        if let data = try? PropertyListSerialization.data(fromPropertyList: meta, format: .xml, options: 0) {
            try? data.write(to: dir.appendingPathComponent("meta.plist"))
        }
    }
}
