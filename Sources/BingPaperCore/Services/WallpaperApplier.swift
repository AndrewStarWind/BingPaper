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

        // Capture current desktop image URLs before restarting WallpaperAgent if we're in Lock Screen Only mode
        // so the temporary backdrop keeps the user's current desktop visible with zero gray flash.
        let lockScreenOnlyFallbackURLs: [CGDirectDisplayID: URL] = await MainActor.run {
            guard target == .lockScreenOnly else { return [:] }
            var map: [CGDirectDisplayID: URL] = [:]
            for screen in NSScreen.screens {
                if let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                   let currentURL = NSWorkspace.shared.desktopImageURL(for: screen),
                   Self.isReadableImageFile(at: currentURL) {
                    map[displayID] = currentURL
                }
            }
            return map
        }

        let backdrop = await MainActor.run { SeamlessBackdropController() }

        do {
            // Cover the desktop layer right before restarting WallpaperAgent so the brief WindowServer void is never visible.
            await MainActor.run {
                backdrop.show(imageForScreen: { screen in
                    if target == .lockScreenOnly {
                        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                            return nil
                        }
                        return lockScreenOnlyFallbackURLs[displayID]
                    }
                    return imageURL
                }, scalingMode: scalingMode)
            }
            // Give WindowServer one frame to composite the backdrop before killing WallpaperAgent.
            try? await Task.sleep(for: .milliseconds(60))

            let previousAgentPID = Self.currentWallpaperAgentPID()
            let result = try indexUpdater.applyWallpaper(
                imageURL: imageURL,
                scalingMode: scalingMode,
                target: target,
                backupDirectory: backupDirectory
            )
            Self.reloadWallpaperAgent()
            await Self.waitForWallpaperAgentReady(previousPID: previousAgentPID)
            await backdrop.fadeOutAndClose(duration: 0.25)

            BingPaperLog.wallpaper.info("Synced Index.plist (\(target.rawValue)) across \(result.scopesUpdated) scope(s) and reloaded WallpaperAgent.")
            return WallpaperApplyReport(
                imagePath: imageURL.path,
                target: target,
                screensUpdated: screensUpdated,
                allSpacesAndLockScreenSynced: true,
                indexScopesUpdated: result.scopesUpdated
            )
        } catch {
            await MainActor.run { backdrop.tearDownImmediately() }
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

    private static func currentWallpaperAgentPID() -> pid_t? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "WallpaperAgent"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8)?
                .split(whereSeparator: \.isNewline)
                .first,
                  let pid = Int32(text.trimmingCharacters(in: .whitespaces)) else {
                return nil
            }
            return pid
        } catch {
            return nil
        }
    }

    /// Waits for launchd to respawn `WallpaperAgent` with a new PID and allows time for `WallpaperImageExtension`
    /// to finish rendering the updated wallpaper underneath our seamless backdrop.
    private static func waitForWallpaperAgentReady(previousPID: pid_t?) async {
        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            if let currentPID = currentWallpaperAgentPID(), currentPID != previousPID {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        // Allow WallpaperImageExtension ~650ms to finish decoding and compositing the new image.
        try? await Task.sleep(for: .milliseconds(650))
    }

    private static func isReadableImageFile(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard url.isFileURL,
              FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              !isDir.boolValue else {
            return false
        }
        let ext = url.pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "heic", "tiff", "webp"].contains(ext)
    }
}
