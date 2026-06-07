# Reversion TV — Apple TV (tvOS)

Native SwiftUI port of the Reversion TV app for Apple TV. Built from
`~/reversion-tv-assets/TV_APP_SPEC.md` (the cross-platform spec); Android TV is
the reference baseline and Tizen (`~/reversion-tv-tizen`) is the closest sibling
to model off.

Backend is always production: `https://reversion.app` (API prefix
`/api/mobile/`).

## Project layout

The Xcode project is **generated** from `project.yml` with
[XcodeGen](https://github.com/yonk/XcodeGen) — source files are globbed from
`Sources/`, so adding a `.swift` file needs no manual project edits.

```
Sources/
  App/        ReversionTVApp.swift (@main), AppRouter.swift, RootView
  Core/       ApiClient, Models, KeychainTokenStore, Prefs, Theme,
              QRCodeGenerator, DeviceInfo
  Screens/    Pairing/ (PairingView + PairingViewModel)
Resources/    Info.plist, Assets.xcassets (brand logos, app icon, accent)
```

## Build / run

```bash
brew install xcodegen        # one-time
xcodegen generate            # regenerate ReversionTV.xcodeproj after adding files
open ReversionTV.xcodeproj   # then hit Run on an Apple TV simulator
```

### First-time setup: tvOS simulator runtime

This machine currently has only iOS simulator runtimes installed. Install the
tvOS platform once (large download) so the simulator and asset catalog compile:

```bash
xcodebuild -downloadPlatform tvOS
```

…or Xcode → Settings → Components → tvOS.

## Implementation status

- [x] Project scaffold + foundations (API client with retry/401→Pairing,
      Keychain token store, prefs, theme, QR generator)
- [x] Pairing (§5): code + QR, countdown, auto-regenerate, poll loop
- [ ] Home (§6) — left nav, hero carousel/spotlight, 4 rails, catalog mode
- [ ] Event Detail (§7)
- [ ] Search (§8)
- [ ] Player full stack (§9)
- [ ] Settings 2-pane + in-app legal reader (§10)
