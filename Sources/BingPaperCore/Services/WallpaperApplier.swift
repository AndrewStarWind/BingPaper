import AppKit
import Foundation

public struct WallpaperApplyReport: Sendable, Equatable {
    public let imagePath: String
    public let target: WallpaperTarget
    public let screensUpdated: Int
    public let allSpacesAndLockScreenSynced: Bool
    public let indexScopesUpdated: Int
    public let warningMessage: String?

    public init(
        imagePath: String,
        target: WallpaperTarget = .allScreensAndLockScreen,
        screensUpdated: Int,
        allSpacesAndLockScreenSynced: Bool,
        indexScopesUpdated: Int,
        warningMessage: String? = nil
    ) {
        self.imagePath = imagePath
        self.target = target
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

/// Applies a wallpaper image to screens, Spaces, and/or the Lock Screen on macOS according to `WallpaperTarget`.
public struct WallpaperApplier: Sendable {
    private let indexUpdater: WallpaperIndexUpdater

    public init(indexUpdater: WallpaperIndexUpdater = WallpaperIndexUpdater()) {
        self.indexUpdater = indexUpdater
    }

    public func applyWallpaper(
        at imageURL: URL,
        scalingMode: WallpaperScalingMode = .fillScreen,
        target: WallpaperTarget = .allScreensAndLockScreen,
        backupDirectory: URL? = nil
    ) async throws -> WallpaperApplyReport {
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            throw WallpaperApplyError.fileMissing(imageURL.path)
        }

        let screensUpdated: Int
        if target == .lockScreenOnly {
            // Do not touch active Desktop screens via NSWorkspace when applying to Lock Screen only.
            screensUpdated = await MainActor.run { NSScreen.screens.count }
        } else {
            screensUpdated = try await MainActor.run {
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

            // Allow WallpaperAgent a brief moment to flush its native Index.plist representation
            // from the NSWorkspace update above so we can clone its exact OS-native EncodedOptionValues.
            try? await Task.sleep(for: .milliseconds(350))
        }

        do {
            let result = try indexUpdater.applyWallpaper(
                imageURL: imageURL,
                scalingMode: scalingMode,
                target: target,
                backupDirectory: backupDirectory
            )
            Self.reloadWallpaperAgent()
            BingPaperLog.wallpaper.info("Synced Index.plist (\(target.rawValue)) across \(result.scopesUpdated) scope(s) and reloaded WallpaperAgent.")
            return WallpaperApplyReport(
                imagePath: imageURL.path,
                target: target,
                screensUpdated: screensUpdated,
                allSpacesAndLockScreenSynced: true,
                indexScopesUpdated: result.scopesUpdated
            )
        } catch {
            if target == .lockScreenOnly {
                throw error
            }
            BingPaperLog.wallpaper.warning("Index.plist sync failed (active screens still updated): \(error.localizedDescription)")
            return WallpaperApplyReport(
                imagePath: imageURL.path,
                target: target,
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
