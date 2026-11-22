import AppKit
import Foundation

public struct WallpaperApplyReport: Sendable, Equatable {
    public let imagePath: String
    public let screensUpdated: Int
    public let allSpacesAndLockScreenSynced: Bool
    public let indexScopesUpdated: Int
    public let warningMessage: String?

    public init(
        imagePath: String,
        screensUpdated: Int,
        allSpacesAndLockScreenSynced: Bool,
        indexScopesUpdated: Int,
        warningMessage: String? = nil
    ) {
        self.imagePath = imagePath
        self.screensUpdated = screensUpdated
        self.allSpacesAndLockScreenSynced = allSpacesAndLockScreenSynced
        self.indexScopesUpdated = indexScopesUpdated
        self.warningMessage = warningMessage
    }
}

public enum WallpaperApplyError: LocalizedError, Sendable {
    case fileMissing(String)
    case noScreensFound
    case workspaceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .fileMissing(let path):
            "Wallpaper file does not exist at \(path)."
        case .noScreensFound:
            "No connected displays were detected."
        case .workspaceFailed(let detail):
            "macOS could not set the desktop wallpaper: \(detail)"
        }
    }
}

/// Applies a wallpaper image to every connected screen, every Space, and the Lock Screen on macOS.
public struct WallpaperApplier: Sendable {
    private let indexUpdater: WallpaperIndexUpdater

    public init(indexUpdater: WallpaperIndexUpdater = WallpaperIndexUpdater()) {
        self.indexUpdater = indexUpdater
    }

    /// Applies `imageURL` across every screen using `NSWorkspace`, then synchronizes `Index.plist`
    /// and reloads `WallpaperAgent` so all Spaces (active & inactive) and the Lock Screen match.
    public func applyWallpaper(
        at imageURL: URL,
        scalingMode: WallpaperScalingMode = .fillScreen,
        syncAllSpacesAndLockScreen: Bool = true,
        backupDirectory: URL? = nil
    ) async throws -> WallpaperApplyReport {
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            throw WallpaperApplyError.fileMissing(imageURL.path)
        }

        let screensUpdated = try await MainActor.run {
            let screens = NSScreen.screens
            guard !screens.isEmpty else {
                throw WallpaperApplyError.noScreensFound
            }
            let options = Self.desktopImageOptions(for: scalingMode)
            for screen in screens {
                do {
                    try NSWorkspace.shared.setDesktopImageURL(imageURL, for: screen, options: options)
                } catch {
                    throw WallpaperApplyError.workspaceFailed(error.localizedDescription)
                }
            }
            return screens.count
        }

        BingPaperLog.wallpaper.info("NSWorkspace updated \(screensUpdated) active screen(s) to \(imageURL.lastPathComponent)")

        guard syncAllSpacesAndLockScreen else {
            return WallpaperApplyReport(
                imagePath: imageURL.path,
                screensUpdated: screensUpdated,
                allSpacesAndLockScreenSynced: false,
                indexScopesUpdated: 0
            )
        }

        // Allow WallpaperAgent a brief moment to flush its native Index.plist representation
        // from the NSWorkspace update above so we can clone its exact OS-native Choice structure.
        try? await Task.sleep(for: .milliseconds(350))

        do {
            let result = try indexUpdater.applyWallpaper(
                imageURL: imageURL,
                scalingMode: scalingMode,
                backupDirectory: backupDirectory
            )
            Self.reloadWallpaperAgent()
            BingPaperLog.wallpaper.info("Synced Index.plist across \(result.scopesUpdated) scope(s) (reusedNative=\(result.reusedNativeChoice)) and reloaded WallpaperAgent.")
            return WallpaperApplyReport(
                imagePath: imageURL.path,
                screensUpdated: screensUpdated,
                allSpacesAndLockScreenSynced: true,
                indexScopesUpdated: result.scopesUpdated
            )
        } catch {
            BingPaperLog.wallpaper.warning("Index.plist sync failed (active screens still updated): \(error.localizedDescription)")
            return WallpaperApplyReport(
                imagePath: imageURL.path,
                screensUpdated: screensUpdated,
                allSpacesAndLockScreenSynced: false,
                indexScopesUpdated: 0,
                warningMessage: error.localizedDescription
            )
        }
    }

    private static func desktopImageOptions(for scalingMode: WallpaperScalingMode) -> [NSWorkspace.DesktopImageOptionKey: Any] {
        switch scalingMode {
        case .fillScreen:
            return [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true
            ]
        case .fitToScreen:
            return [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: false,
                .fillColor: NSColor.black
            ]
        case .stretchToFill:
            return [
                .imageScaling: NSImageScaling.scaleAxesIndependently.rawValue,
                .allowClipping: true
            ]
        case .center:
            return [
                .imageScaling: NSImageScaling.scaleNone.rawValue,
                .allowClipping: false,
                .fillColor: NSColor.black
            ]
        }
    }

    private static func reloadWallpaperAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["WallpaperAgent"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            BingPaperLog.wallpaper.warning("Failed to restart WallpaperAgent: \(error.localizedDescription)")
        }
    }
}
