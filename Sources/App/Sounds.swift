import AppKit

enum Sounds {
    private static let spookyNames = ["ghost", "organ", "bell"]
    private static var lastSpooky: String?
    private static var playing: [NSSound] = []

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "soundsOn") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "soundsOn") }
    }

    /// A random Halloween sound, never the same one twice in a row.
    static func spooky() {
        let name = spookyNames.filter { $0 != lastSpooky }.randomElement()!
        lastSpooky = name
        play(name)
    }

    /// The sparkly fanfare for a Shiny pull.
    static func sparkle() {
        play("shiny")
    }

    private static func play(_ name: String) {
        guard enabled, let url = Bundle.main.url(forResource: name, withExtension: "m4a"),
              let sound = NSSound(contentsOf: url, byReference: true) else { return }
        playing.removeAll { !$0.isPlaying }
        playing.append(sound) // NSSound stops if it's deallocated mid-play.
        sound.play()
    }
}
