import Foundation

/// One gacha result: a costume, possibly in its golden Shiny form.
struct Pull: Equatable {
    let costume: Costume
    let shiny: Bool

    var id: String { costume.rawValue + (shiny ? "+shiny" : "") }
    var title: String { shiny ? "Shiny \(costume.displayName)" : costume.displayName }

    init(costume: Costume, shiny: Bool) {
        self.costume = costume
        self.shiny = shiny
    }

    init?(id: String) {
        let parts = id.split(separator: "+")
        guard let costume = parts.first.flatMap({ Costume(rawValue: String($0)) }) else { return nil }
        self.init(costume: costume, shiny: parts.dropFirst().first == "shiny")
    }

    /// Every collectible: each costume in normal and Shiny form.
    static var all: [Pull] {
        [false, true].flatMap { shiny in Costume.allCases.map { Pull(costume: $0, shiny: shiny) } }
    }
}

final class Gacha {
    static let shared = Gacha()
    static let shinyChance = 0.05
    /// A Shiny is guaranteed by this pull at the latest.
    static let pityLimit = 20

    var store = UserDefaults.standard

    var collected: Set<String> {
        get { Set(store.stringArray(forKey: "collected") ?? []) }
        set { store.set(newValue.sorted(), forKey: "collected") }
    }

    var totalPulls: Int {
        get { store.integer(forKey: "totalPulls") }
        set { store.set(newValue, forKey: "totalPulls") }
    }

    var pullsSinceShiny: Int {
        get { store.integer(forKey: "pullsSinceShiny") }
        set { store.set(newValue, forKey: "pullsSinceShiny") }
    }

    /// Rolls a costume, never repeating the one the folder is already wearing.
    func roll(avoiding current: Costume?) -> (pull: Pull, isNew: Bool) {
        totalPulls += 1
        let shiny = pullsSinceShiny + 1 >= Self.pityLimit || Double.random(in: 0..<1) < Self.shinyChance
        pullsSinceShiny = shiny ? 0 : pullsSinceShiny + 1

        // Every costume is equally likely.
        let pick = Costume.allCases.filter { $0 != current }.randomElement()!
        let pull = Pull(costume: pick, shiny: shiny)
        let isNew = !collected.contains(pull.id)
        if isNew { collected.insert(pull.id) }
        return (pull, isNew)
    }
}
