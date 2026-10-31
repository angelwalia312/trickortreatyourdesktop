# 🎃 Trick or Treat

A Halloween toy for macOS. Right-click any file or folder on your Desktop and choose **🎃 Trick or Treat**.
It gets a random costume, with gacha-style rarities and a collection to complete.

Files keep their Finder preview under the costume (a screenshot stays a screenshot wearing a witch hat), and
costumes reshape themselves to fit wide or tall files. Only the icon changes: file contents and modification dates
are never touched. Apps and aliases are left alone, because changing an app's icon would break its code signature.

There are six costumes, each equally likely: Ghost, Witch, Jack-o'-Lantern, Mummy, Vampire and Frankenstein.
Re-rolling never repeats the costume an item is already wearing. Any costume can also come out **Shiny**, all in
gold (5% of pulls, guaranteed within 20), which makes 12 to collect.

- **🧹 Undecorate** (right-click a costumed item) takes its costume off and restores exactly the icon it had before.
- **🧹 Undecorate Desktop** takes off every costume on the Desktop. It's in the menu when you right-click empty
  Desktop space, and also when you right-click any item sitting on the Desktop.
- Open the app itself to see your collection, turn sounds off, or undecorate everything.

## How it works

- `Sources/Extension/FinderSync.swift`: a sandboxed Finder Sync extension that adds the menu items on
  `~/Desktop`. It hands each choice to the app as a `trickortreat://` link.
- `Sources/App/`: the app, which runs in the background with no Dock icon.
  - `Costumes.swift` draws every costume in code on top of the item's current look.
  - `Decorator.swift` sets the custom icon and keeps a backup of the original look in
    `~/Library/Application Support/Trick or Treat/Backups`. It also tags the folder with extended attributes.
  - `Gacha.swift` handles rarity odds, the Shiny pity counter and the collection.
  - `Popup.swift` is the reveal card, and `Home.swift` is the collection window.
- `Tools/make_sounds.py` synthesises the sound effects from scratch, so there are no audio licences.

## Building

Only Apple's Command Line Tools are needed (`xcode-select --install`), not Xcode.

```bash
./build.sh
```

This produces `build/Trick or Treat.app` and `build/TrickOrTreat-1.0.dmg`, ad-hoc signed. That build
runs fine on this Mac. Other Macs will show an "Apple could not verify…" warning.

### Signed and notarized release (no warnings for anyone)

1. Join the Apple Developer Program ($99/year) at https://developer.apple.com/programs/enroll/.
2. In the developer portal, create a **Developer ID Application** certificate and install it in Keychain.
3. Store notarization credentials once (uses an app-specific password from appleid.apple.com):
   ```bash
   xcrun notarytool store-credentials trickortreat --apple-id YOU@EXAMPLE.COM --team-id TEAMID
   ```
4. Build:
   ```bash
   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=trickortreat ./build.sh
   ```

## Website

`docs/` is a static launch page (`index.html`, images and the DMG, which `build.sh` copies in). To publish it on
GitHub Pages:

1. Create a public repository on GitHub, e.g. `trick-or-treat`, and push this folder to it.
2. In the repository, open **Settings › Pages**, set **Source** to *Deploy from a branch*, then pick `main` and
   `/docs` and save. The site appears at `https://YOUR-USERNAME.github.io/trick-or-treat/` within a minute or two.
3. For image previews when the link is shared on Twitter/X, change the `og:image` line in `docs/index.html` to
   the full address of `social-card.png`.

To preview locally: `python3 -m http.server 8642 --directory docs`, then open http://localhost:8642.

`docs/tutorial.gif` is drawn by `Tools/tutorial/main.swift` using the app's real costume art and reveal card:

```bash
swiftc -swift-version 5 -O Sources/App/{Costumes,Gacha,Popup}.swift Tools/tutorial/main.swift -o /tmp/tutorial
/tmp/tutorial docs/tutorial.gif
```

## Installing

1. Open the DMG and drag **Trick or Treat** to Applications.
2. Open it once. The window shows **Open Settings**: switch on the *Trick or Treat* Finder extension.
3. Right-click a file or folder on the Desktop and choose **🎃 Trick or Treat**. The first time, allow Desktop access.
