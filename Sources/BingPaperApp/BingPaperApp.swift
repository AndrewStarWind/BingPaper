import AppKit
import BingPaperCore
import SwiftUI

@main
@MainActor
struct BingPaperLauncher {
    static func main() {
        let args = Set(CommandLine.arguments.dropFirst())
        if args.contains("--help") || args.contains("-h") {
            print("""
            BingPaper — Daily Bing Wallpaper for macOS

            Usage:
              BingPaper                Launch the menu bar application
              BingPaper --update-now   Fetch and apply today's Bing wallpaper to all screens & Lock Screen, then exit
              BingPaper --help         Show this help message
            """)
            return
        }

        if args.contains("--update-now") {
            runHeadlessUpdateAndExit()
            return
        }

        BingPaperApp.main()
    }

    private static func runHeadlessUpdateAndExit() {
        // Initialize AppKit so NSScreen.screens and NSWorkspace are available.
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        let semaphore = DispatchSemaphore(value: 0)
        final class ExitBox: @unchecked Sendable {
            var code: Int32 = 0
        }
        let exitBox = ExitBox()

        Task {
            do {
                let settings = AppSettings.load()
                let market = settings.market.resolvedMarketCode()
                let api = BingAPIClient()
                let store = WallpaperStore()
                let applier = WallpaperApplier()

                let metadata = try await api.fetchTodayMetadata(market: market)
                let fileURL: URL
                if let existing = store.existingFileURL(for: metadata, market: market, preferUHD: settings.preferUHD) {
                    fileURL = existing
                } else {
                    let (data, _) = try await api.downloadImageData(for: metadata, preferUHD: settings.preferUHD)
                    let entry = try store.saveImage(data, metadata: metadata, market: market, preferUHD: settings.preferUHD, appliedAt: Date())
                    fileURL = entry.fileURL
                }

                let report = try await applier.applyWallpaper(
                    at: fileURL,
                    scalingMode: settings.scalingMode,
                    target: settings.wallpaperTarget,
                    backupDirectory: store.backupsDirectory
                )
                _ = try? store.pruneOldWallpapers(retentionDays: settings.retentionDays, keeping: fileURL.path)

                print("BingPaper updated: \(metadata.displayTitle) (\(metadata.startdate))")
                print("Target: \(report.target.displayName), Screens: \(report.screensUpdated), Synced: \(report.allSpacesAndLockScreenSynced) (\(report.indexScopesUpdated) scopes)")
                if let warning = report.warningMessage {
                    fputs("Warning: \(warning)\n", stderr)
                }
            } catch {
                fputs("BingPaper update failed: \(error.localizedDescription)\n", stderr)
                exitBox.code = 1
            }
            semaphore.signal()
        }

        // Pump main run loop while the async task completes on MainActor.
        while semaphore.wait(timeout: .now() + 0.05) == .timedOut {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        exit(exitBox.code)
    }
}

struct BingPaperApp: App {
    private let viewModel: WallpaperViewModel

    init() {
        let vm = WallpaperViewModel()
        vm.start()
        self.viewModel = vm
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(viewModel: viewModel)
        } label: {
            Image(systemName: viewModel.isUpdating ? "arrow.trianglehead.2.clockwise" : "photo.on.rectangle.angled")
                .accessibilityLabel("BingPaper")
        }
        .menuBarExtraStyle(.window)

        Window("BingPaper Settings", id: "settings") {
            SettingsView(viewModel: viewModel)
        }
        .windowResizability(.contentSize)
    }
}
