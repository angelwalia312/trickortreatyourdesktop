import AppKit
import FinderSync
import SwiftUI

final class HomeModel: ObservableObject {
    @Published var extensionEnabled = FIFinderSyncController.isExtensionEnabled
    @Published var collected = Gacha.shared.collected
    @Published var totalPulls = Gacha.shared.totalPulls
    @Published var pity = Gacha.pityLimit - Gacha.shared.pullsSinceShiny
    @Published var thumbnails: [String: NSImage] = [:]
    @Published var soundsOn = Sounds.enabled {
        didSet { Sounds.enabled = soundsOn }
    }

    var undressEverything: () -> Void = {}

    func refresh() {
        extensionEnabled = FIFinderSyncController.isExtensionEnabled
        collected = Gacha.shared.collected
        totalPulls = Gacha.shared.totalPulls
        pity = Gacha.pityLimit - Gacha.shared.pullsSinceShiny
    }

    func loadThumbnails(synchronously: Bool = false) {
        guard thumbnails.isEmpty else { return }
        let work = {
            let base = NSWorkspace.shared.icon(for: .folder)
            var images: [String: NSImage] = [:]
            for pull in Pull.all {
                images[pull.id] = CostumeRenderer.nsImage(CostumeRenderer.render(pull.costume, shiny: pull.shiny, base: base))
            }
            return images
        }
        if synchronously {
            thumbnails = work()
        } else {
            DispatchQueue.global(qos: .userInitiated).async {
                let images = work()
                DispatchQueue.main.async { self.thumbnails = images }
            }
        }
    }
}

/// The window people see when they open the app: setup, their costume collection and settings.
struct HomeView: View {
    @ObservedObject var model: HomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp?.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trick or Treat")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                    Text("Right-click any file or folder on your Desktop and choose **🎃 Trick or Treat**. Every pull is a surprise costume.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }

            if !model.extensionEnabled { setupCard }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Your collection")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("\(model.collected.count)/\(Pull.all.count)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.gold)
                    Spacer()
                    Text("\(model.totalPulls) pulls  ·  Shiny guaranteed within \(model.pity)")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
                    ForEach(Pull.all, id: \.id) { pull in card(pull) }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.06)))

            HStack(spacing: 12) {
                Toggle("Spooky sounds", isOn: $model.soundsOn)
                    .toggleStyle(.switch)
                Spacer()
                Button("Undecorate Everything") { model.undressEverything() }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .font(.system(size: 13, design: .rounded))
        }
        .padding(24)
        .frame(width: 660)
        .foregroundStyle(.white)
        .background(SpookyBackground(glow: Color(red: 1, green: 0.5, blue: 0.1)))
        .environment(\.colorScheme, .dark)
    }

    private var setupCard: some View {
        HStack(spacing: 14) {
            Text("👻").font(.system(size: 34))
            VStack(alignment: .leading, spacing: 3) {
                Text("One quick step: switch on the Finder extension")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text("macOS keeps new Finder extensions off. Turn on **Trick or Treat** in the list that opens.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer()
            Button("Open Settings") { FIFinderSyncController.showExtensionManagementInterface() }
                .controlSize(.large)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.orange.opacity(0.22)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.orange.opacity(0.6), lineWidth: 1))
    }

    private func card(_ pull: Pull) -> some View {
        let owned = model.collected.contains(pull.id)
        return VStack(spacing: 4) {
            ZStack {
                if let image = model.thumbnails[pull.id] {
                    if owned {
                        Image(nsImage: image).resizable().interpolation(.high)
                    } else {
                        Image(nsImage: image).resizable().colorMultiply(.black).opacity(0.35)
                        Text("?").font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(.white.opacity(0.5))
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 84, height: 84)
            Text(owned ? pull.title : "???")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(owned && pull.shiny ? Palette.gold.opacity(0.16) : .white.opacity(0.04)))
    }
}
