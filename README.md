# BingPaper

A native macOS menu bar application built with **Swift 6** and **SwiftUI** (targeting **macOS 26+ / macOS 27** with Liquid Glass) that automatically downloads the **Bing Daily Image** in 4K UHD and applies it every day to **every connected display, every Space (active and inactive), and the Lock Screen**.

<p align="center">
  <img src="docs/screenshot.jpg" alt="BingPaper Menu Bar Popover" width="380" />
</p>

<p align="center">
  <a href="https://buymeacoffee.com/sevasdreas">
    <img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-Support%20BingPaper-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black" alt="Buy Me a Coffee" />
  </a>
</p>

## Features

- **Flexible Target Selection (Screens, Spaces & Lock Screen)**:
  - Choose in Settings → **Wallpaper** whether to apply Bing's daily image to **All Screens, Spaces & Lock Screen**, **Screens & Spaces Only**, or **Lock Screen Only**.
  - Updates connected displays via `NSWorkspace.shared.setDesktopImageURL` and synchronizes macOS's native `WallpaperAgent` store (`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`) using macOS 27's native binary plist schema, then restarts `WallpaperAgent`.
  - Preserves your non-BingPaper Screen Saver (`Idle`) setting and saves a one-time initial backup of your original `Index.plist` in `~/Library/Application Support/BingPaper/Backups/`.
  - Automatically re-applies today's wallpaper when external monitors are connected or rearranged.
- **Automatic Daily Updates**:
  - Runs at your chosen daily schedule time (default `09:00`).
  - Automatically catches up on **launch**, **wake from sleep**, **calendar day rollover**, or **network reconnect** if your Mac was asleep or offline.
  - Tracks Bing's own `startdate` so timezone offsets never cause a missed daily photo.
  - Native **Launch at Login** support via `SMAppService.mainApp`.
- **Clean Menu Bar UI**:
  - Lives quietly in the macOS menu bar with Liquid Glass controls.
  - **Live Background Preview** with an on-preview **Set as Background** button / **Active** indicator.
  - **Previous Days Strip**: Browse chronologically from older days on the left to **Today** on the right (covers the last 8 Bing daily photos plus older cached days) and switch wallpapers with one click.
  - **4K UHD + Regional Markets**: Downloads `_UHD.jpg` (4K) with automatic `1920x1080` fallback, supports multiple Bing regions, Save Copy, and automatic cache cleanup.
- **Headless CLI Mode**:
  - Run `BingPaper.app/Contents/MacOS/BingPaper --update-now` to fetch and apply today's wallpaper immediately from Terminal or scripts.

## Download

Grab the latest pre-built `BingPaper-v1.1.0-macos.zip` from the [Releases](../../releases) page, unzip it, and move `BingPaper.app` to `/Applications`.

> **Note:** Because the release build is ad-hoc signed, if macOS Gatekeeper warns on first launch, right-click `BingPaper.app` → **Open**, or build locally from source below.

## Building from Source

Requires macOS 26+ (built and tested on macOS 27.2.1 with Swift 6.4.2 Command Line Tools — Xcode is not required).

```bash
# Build the signed BingPaper.app bundle into ./dist/BingPaper.app
./Scripts/build-app.sh

# Or build and copy directly into /Applications/BingPaper.app
./Scripts/install.sh

# Launch the app
open /Applications/BingPaper.app
```

## Running Tests

```bash
swift test
```

## Note on FileVault Pre-Boot Login Screen

When **FileVault** full-disk encryption is enabled, macOS displays a system-protected wallpaper on the initial pre-boot unlock screen before your home directory is decrypted. Once unlocked, **every Lock Screen** (when locking your Mac or waking from sleep), **every display**, and **every Space** displays today's Bing wallpaper.

## Support

If you find BingPaper useful, consider supporting its development:

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-sevasdreas-FFDD00?style=flat-square&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/sevasdreas)

## License

MIT License — © 2026 Andrey Ivanov. See [LICENSE](LICENSE) for details.
